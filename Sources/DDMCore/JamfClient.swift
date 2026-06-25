import Foundation

/// OAuth2 client-credentials exchange for the Jamf Platform API.
///
/// Mirrors Jamf's own Go SDK: `POST {baseURL}/auth/token` with
/// `grant_type=client_credentials`. The SDK uses oauth2 `AuthStyleAuto`, which
/// tries HTTP Basic auth first and falls back to credentials in the form body —
/// we do the same so it works against either server preference.
///
/// Credentials come only from the environment (`JAMF_CLIENT_ID` /
/// `JAMF_CLIENT_SECRET`) — never flags, never logged. The request builder is
/// separated so it's unit-testable without a live token endpoint.
public enum JamfAuth {

    public enum Style { case basicHeader, bodyParams }

    public static func tokenURL(baseURLString: String) -> URL? {
        var s = baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        if !s.contains("://") { s = "https://" + s }
        while s.hasSuffix("/") { s.removeLast() }
        return URL(string: s + "/auth/token")
    }

    /// Build a token request in the given auth style. Pure — no I/O.
    public static func makeTokenRequest(tokenURL: URL, clientID: String,
                                        clientSecret: String, style: Style) -> URLRequest {
        var req = URLRequest(url: tokenURL)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        var params = ["grant_type": "client_credentials"]
        switch style {
        case .basicHeader:
            let creds = Data("\(clientID):\(clientSecret)".utf8).base64EncodedString()
            req.setValue("Basic \(creds)", forHTTPHeaderField: "Authorization")
        case .bodyParams:
            params["client_id"] = clientID
            params["client_secret"] = clientSecret
        }
        req.httpBody = Data(formEncode(params).utf8)
        return req
    }

    /// Fetch a bearer token. Tries Basic-header auth, then body-params. Returns
    /// the token or an error message. Synchronous.
    public static func fetchToken(baseURLString: String, clientID: String,
                                  clientSecret: String,
                                  session: URLSession = .shared) -> (token: String?, error: String?) {
        guard let url = tokenURL(baseURLString: baseURLString) else {
            return (nil, "invalid --jamf-url")
        }
        var lastError = "no response"
        for style in [Style.basicHeader, .bodyParams] {
            let req = makeTokenRequest(tokenURL: url, clientID: clientID,
                                       clientSecret: clientSecret, style: style)
            let (data, code, err) = perform(req, session: session)
            if let err { lastError = err; continue }
            if (200...299).contains(code),
               let data,
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let token = obj["access_token"] as? String, !token.isEmpty {
                return (token, nil)
            }
            // Surface a useful message and try the next style.
            if let data, let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                lastError = (obj["error_description"] as? String)
                    ?? (obj["error"] as? String) ?? "HTTP \(code)"
            } else {
                lastError = "HTTP \(code)"
            }
        }
        return (nil, lastError)
    }

    private static func perform(_ req: URLRequest, session: URLSession) -> (Data?, Int, String?) {
        let sem = DispatchSemaphore(value: 0)
        var out: (Data?, Int, String?) = (nil, 0, nil)
        let task = session.dataTask(with: req) { data, resp, err in
            defer { sem.signal() }
            if let err { out = (nil, 0, err.localizedDescription); return }
            out = (data, (resp as? HTTPURLResponse)?.statusCode ?? 0, nil)
        }
        task.resume()
        sem.wait()
        return out
    }

    private static func formEncode(_ params: [String: String]) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return params.map { k, v in
            let ek = k.addingPercentEncoding(withAllowedCharacters: allowed) ?? k
            let ev = v.addingPercentEncoding(withAllowedCharacters: allowed) ?? v
            return "\(ek)=\(ev)"
        }.sorted().joined(separator: "&")
    }
}

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
