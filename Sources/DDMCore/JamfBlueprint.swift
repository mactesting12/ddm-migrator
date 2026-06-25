import Foundation

/// Builds a Jamf Platform API "create blueprint" request body from a migration
/// report. Pure (no I/O) so it's fully unit-testable; `JamfClient` posts it.
///
/// Schema (confirmed from Jamf's public Terraform provider + Go SDK):
///   POST /api/blueprints/v1/tenant/{tenantId}/blueprints
///   { name, description?, scope: { deviceGroups: [] }, steps: [ { components: [...] } ] }
///
/// Two component types are used:
///   • `com.jamf.ddm.custom-declarations` — carries our migrated / fanned-out
///     declarations as { type, channelType, kind, payload, payloadKey }. Jamf
///     generates the Identifier/ServerToken, so we send the Payload object only.
///   • `com.jamf.ddm-configuration-profile` — delivers raw Apple payloads
///     (payloadContent[]). We use it for legacy-wrapped payloads, sending the
///     preserved original payload — so Jamf needs no hosted ProfileURL.
public enum JamfBlueprint {

    public struct Result: Sendable {
        public let body: JSONValue
        public let customDeclarationCount: Int
        public let legacyProfileCount: Int
        public let skipped: [String]
    }

    public static let customDeclarationsIdentifier = "com.jamf.ddm.custom-declarations"
    public static let configurationProfileIdentifier = "com.jamf.ddm-configuration-profile"

    public static func build(report: MigrationReport,
                             name: String,
                             description: String?,
                             deviceGroups: [String],
                             channel: String = "SYSTEM",
                             includeLegacy: Bool = false) -> Result {
        var customDeclarations: [JSONValue] = []
        var legacyContent: [JSONValue] = []
        var skipped: [String] = []
        var payloadKey = 1

        for profile in report.results {
            for p in profile.payloads where !p.producedDeclarations.isEmpty {
                if p.classification == .legacyWrapped {
                    guard includeLegacy else { continue }
                    if let item = legacyProfileItem(p.preservedSource) {
                        legacyContent.append(item)
                    } else {
                        skipped.append("\(p.sourceType) (legacy, #\(p.sourceIndex)) — not a raw Apple payload; configure manually")
                    }
                    continue
                }
                // migrated / fanned-out → custom declarations
                for decl in p.producedDeclarations {
                    customDeclarations.append(.object([
                        "type": .string(decl.type),
                        "channelType": .string(channel),
                        "kind": .string("CONFIGURATION"),
                        "payload": decl.payload,
                        "payloadKey": .int(payloadKey),
                    ]))
                    payloadKey += 1
                }
            }
        }

        var components: [JSONValue] = []
        if !customDeclarations.isEmpty {
            components.append(.object([
                "identifier": .string(customDeclarationsIdentifier),
                "configuration": .object(["declarations": .array(customDeclarations)]),
            ]))
        }
        if !legacyContent.isEmpty {
            components.append(.object([
                "identifier": .string(configurationProfileIdentifier),
                "configuration": .object([
                    "payloadDisplayName": .string("\(name) — legacy payloads"),
                    "payloadContent": .array(legacyContent),
                ]),
            ]))
        }

        var body: [String: JSONValue] = [
            "name": .string(name),
            "scope": .object(["deviceGroups": .array(deviceGroups.map { .string($0) })]),
            "steps": .array([.object(["components": .array(components)])]),
        ]
        if let description { body["description"] = .string(description) }

        return Result(body: .object(body),
                      customDeclarationCount: customDeclarations.count,
                      legacyProfileCount: legacyContent.count,
                      skipped: skipped)
    }

    /// Convert a preserved legacy payload into a `payloadContent` item:
    /// `{ "payloadType": <type>, <non-meta keys…> }`. Returns nil for payloads
    /// we reshaped (MCX), which aren't a deployable raw profile payload.
    static func legacyProfileItem(_ preserved: JSONValue?) -> JSONValue? {
        guard let obj = preserved?.objectValue,
              case let .string(type)? = obj["PayloadType"],
              type != "com.apple.ManagedClient.preferences" else {
            return nil
        }
        var item: [String: JSONValue] = ["payloadType": .string(type)]
        for (k, v) in obj where !Transformers.payloadMetaKeys.contains(k) {
            item[k] = v
        }
        return .object(item)
    }
}
