import Foundation

/// Minimal client for the Jamf Platform API "create blueprint" endpoint:
/// `POST /api/blueprints/v1/tenant/{tenantId}/blueprints` (JSON, Bearer auth).
///
/// Like the Fleet client, this is strictly opt-in (`--push-jamf`) and the token
/// comes only from the `JAMF_API_TOKEN` environment variable — never a flag,
/// never logged. Obtaining that bearer token (Jamf API-client OAuth2
/// client-credentials against the Jamf account) is done out of band for now;
/// the client-credentials exchange can be added once confirmed against a tenant.
///
/// The request builder is separated from the network call so it can be
/// unit-tested without a live tenant.
public struct JamfClient {

    public struct CreateResult: Sendable {
        public let statusCode: Int
        public let blueprintID: String?
        public let message: String?
        public var success: Bool { (200...299).contains(statusCode) }
    }

    public let endpoint: URL
    public let token: String
    private let session: URLSession

    /// - Parameters:
    ///   - baseURLString: gateway base, e.g. `https://us.apigw.jamf.com` (scheme optional).
    ///   - tenantID: the Jamf tenant id.
    public init?(baseURLString: String, tenantID: String, token: String, session: URLSession = .shared) {
        var s = baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        let tenant = tenantID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty, !tenant.isEmpty, !token.isEmpty else { return nil }
        if !s.contains("://") { s = "https://" + s }
        while s.hasSuffix("/") { s.removeLast() }
        guard let url = URL(string: s + "/api/blueprints/v1/tenant/\(tenant)/blueprints") else { return nil }
        self.endpoint = url
        self.token = token
        self.session = session
    }

    /// Build the create-blueprint request. Pure — no I/O.
    public func makeCreateRequest(body: Data) -> URLRequest {
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.httpBody = body
        return req
    }

    /// Create the blueprint. Synchronous so it composes with the CLI.
    public func create(body: Data) -> CreateResult {
        let req = makeCreateRequest(body: body)
        let sem = DispatchSemaphore(value: 0)
        var result = CreateResult(statusCode: 0, blueprintID: nil, message: "no response")
        let task = session.dataTask(with: req) { data, resp, err in
            defer { sem.signal() }
            if let err {
                result = CreateResult(statusCode: 0, blueprintID: nil, message: err.localizedDescription)
                return
            }
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            var id: String?
            var message: String?
            if let data, !data.isEmpty,
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                id = (obj["id"] as? String) ?? (obj["href"] as? String)
                message = (obj["message"] as? String)
                    ?? ((obj["errors"] as? [[String: Any]])?.first?["detail"] as? String)
            }
            result = CreateResult(statusCode: code, blueprintID: id, message: message)
        }
        task.resume()
        sem.wait()
        return result
    }
}
