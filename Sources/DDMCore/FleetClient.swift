import Foundation

/// Minimal client for Fleet's "Create configuration profile" endpoint:
/// `POST /api/v1/fleet/configuration_profiles` (multipart/form-data, Bearer
/// auth). Fleet accepts a DDM declaration `.json` in the same `profile` field
/// it uses for `.mobileconfig`, so we upload our `.ddm.json` files as-is.
///
/// This is the one place DDM Migrator talks to an MDM over the network, and
/// it's strictly opt-in (CLI `--push-fleet`). The API token is read from the
/// `FLEET_API_TOKEN` environment variable — never a flag (stays out of shell
/// history / process listings) and never logged.
///
/// The request builder (`makeUploadRequest`) is separated from the network call
/// so it can be unit-tested without a live server.
public struct FleetClient {

    public struct UploadResult: Sendable {
        public let name: String
        public let statusCode: Int
        public let profileUUID: String?
        public let message: String?
        /// True for 2xx; 409 (already exists) is reported separately as `exists`.
        public var success: Bool { (200...299).contains(statusCode) }
        public var exists: Bool { statusCode == 409 }
    }

    public let endpoint: URL
    public let token: String
    private let session: URLSession

    /// - Parameter baseURL: the Fleet server URL (scheme optional; https assumed).
    public init?(baseURLString: String, token: String, session: URLSession = .shared) {
        var s = baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty, !token.isEmpty else { return nil }
        if !s.contains("://") { s = "https://" + s }
        while s.hasSuffix("/") { s.removeLast() }
        guard let url = URL(string: s + "/api/v1/fleet/configuration_profiles") else { return nil }
        self.endpoint = url
        self.token = token
        self.session = session
    }

    /// Build the multipart upload request. Pure — no I/O — so tests can inspect it.
    public func makeUploadRequest(fileName: String,
                                  data: Data,
                                  teamID: String?,
                                  teamFieldName: String = "team_id") -> URLRequest {
        let boundary = "ddm-migrate-\(UUID().uuidString)"
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        func append(_ s: String) { body.append(Data(s.utf8)) }

        if let teamID, !teamID.isEmpty {
            append("--\(boundary)\r\n")
            append("Content-Disposition: form-data; name=\"\(teamFieldName)\"\r\n\r\n")
            append("\(teamID)\r\n")
        }
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"profile\"; filename=\"\(fileName)\"\r\n")
        append("Content-Type: application/octet-stream\r\n\r\n")
        body.append(data)
        append("\r\n--\(boundary)--\r\n")

        req.httpBody = body
        return req
    }

    /// Upload one declaration. Synchronous (blocks until the request completes)
    /// so it composes cleanly with the CLI.
    public func upload(fileName: String,
                       data: Data,
                       teamID: String?,
                       teamFieldName: String = "team_id") -> UploadResult {
        let req = makeUploadRequest(fileName: fileName, data: data,
                                    teamID: teamID, teamFieldName: teamFieldName)
        let sem = DispatchSemaphore(value: 0)
        var result = UploadResult(name: fileName, statusCode: 0,
                                  profileUUID: nil, message: "no response")
        let task = session.dataTask(with: req) { data, resp, err in
            defer { sem.signal() }
            if let err {
                result = UploadResult(name: fileName, statusCode: 0,
                                      profileUUID: nil, message: err.localizedDescription)
                return
            }
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            var uuid: String?
            var message: String?
            if let data, !data.isEmpty,
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                uuid = obj["profile_uuid"] as? String
                // Fleet error bodies vary; surface a useful message if present.
                message = (obj["message"] as? String)
                    ?? ((obj["errors"] as? [[String: Any]])?.first?["reason"] as? String)
            }
            result = UploadResult(name: fileName, statusCode: code,
                                  profileUUID: uuid, message: message)
        }
        task.resume()
        sem.wait()
        return result
    }
}
