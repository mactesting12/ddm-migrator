import Foundation

/// The public entry point to the engine. Runs the full pipeline for one input
/// `.mobileconfig`:
///
///   2a decode CMS/plist → 2b walk + route payloads → 2c MCX / 2d fan-out /
///   2e legacy wrap → a `ProfileResult` describing everything that happened.
///
/// Pure and synchronous — no UI, no global state, safe to call off the main
/// thread and from tests.
public struct Migrator {
    public init() {}

    /// Migrate a file on disk. Never throws — file-level failures become a
    /// `ProfileResult` with `.error` set, so a bad file in a batch can't take
    /// down the whole run or the UI.
    public func migrate(fileURL: URL) -> ProfileResult {
        let name = fileURL.lastPathComponent
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            return ProfileResult(fileName: name, sourceFormat: nil,
                                 profileIdentifier: nil, profileDisplayName: nil,
                                 payloads: [], error: "Could not read file: \(error.localizedDescription)")
        }
        return migrate(data: data, fileName: name)
    }

    /// Migrate raw bytes (used by tests and the file path above).
    public func migrate(data: Data, fileName: String) -> ProfileResult {
        // 2a — recover the plist (handles CMS-wrapped and raw).
        let plistData: Data
        let format: SourceFormat
        do {
            (plistData, format) = try ProfileDecoder.recoverPlist(from: data)
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return ProfileResult(fileName: fileName, sourceFormat: nil,
                                 profileIdentifier: nil, profileDisplayName: nil,
                                 payloads: [], error: message)
        }

        // Parse the plist into a dictionary.
        let root: [String: Any]
        do {
            let obj = try PropertyListSerialization.propertyList(from: plistData, options: [], format: nil)
            guard let dict = obj as? [String: Any] else {
                return ProfileResult(fileName: fileName, sourceFormat: format,
                                     profileIdentifier: nil, profileDisplayName: nil,
                                     payloads: [], error: "Profile root is not a dictionary.")
            }
            root = dict
        } catch {
            return ProfileResult(fileName: fileName, sourceFormat: format,
                                 profileIdentifier: nil, profileDisplayName: nil,
                                 payloads: [], error: "Could not parse profile plist: \(error.localizedDescription)")
        }

        let profileID = root["PayloadIdentifier"] as? String
        let profileName = root["PayloadDisplayName"] as? String

        guard let content = root["PayloadContent"] as? [[String: Any]] else {
            // A profile with no PayloadContent: not necessarily an error, but
            // nothing to migrate. Treat as error so the UI flags it clearly.
            return ProfileResult(fileName: fileName, sourceFormat: format,
                                 profileIdentifier: profileID, profileDisplayName: profileName,
                                 payloads: [], error: "Profile has no PayloadContent array.")
        }

        // 2b — walk + route each payload.
        var payloadResults: [PayloadResult] = []
        for (index, payload) in content.enumerated() {
            let type = payload["PayloadType"] as? String ?? "(missing PayloadType)"
            payloadResults.append(contentsOf: route(type: type, payload: payload,
                                                     sourceIndex: index, profileID: profileID))
        }

        return ProfileResult(fileName: fileName, sourceFormat: format,
                             profileIdentifier: profileID, profileDisplayName: profileName,
                             payloads: payloadResults, error: nil)
    }

    /// Route one payload through the data-driven mapping table (stage 2b).
    private func route(type: String, payload: [String: Any],
                       sourceIndex: Int, profileID: String?) -> [PayloadResult] {
        switch MappingTable.handler(for: type) {
        case .fanOut:
            return Transformers.fanOutApplicationAccess(
                payload: payload, sourceIndex: sourceIndex, profileID: profileID)
        case .mcx:
            return Transformers.unwrapMCX(
                payload: payload, sourceIndex: sourceIndex, profileID: profileID)
        case .direct(let domain, let keys):
            return Transformers.direct(
                domain: domain, keys: keys, payload: payload,
                sourceIndex: sourceIndex, profileID: profileID)
        case .knownLegacy(let reason):
            let (jv, lossy) = JSONValue.fromPlist(payload)
            let decl = Transformers.makeLegacyDeclaration(
                preserved: jv, profileID: profileID, sourceIndex: sourceIndex, salt: type)
            var fullReason = reason
            if lossy {
                fullReason += " (Note: payload contained Date/Data values, preserved as ISO8601/base64 strings.)"
            }
            return [PayloadResult(
                sourceType: type,
                sourceIndex: sourceIndex,
                sourceDisplayName: payload["PayloadDisplayName"] as? String,
                classification: .legacyWrapped,
                targetDomains: [LegacyWrap.legacyDomain],
                reason: fullReason,
                producedDeclarations: [decl],
                preservedSource: jv)]
        }
    }
}
