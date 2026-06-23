import Foundation

/// Stage 2b — the top-level payload-type routing table.
///
/// Instead of an `if/else` sprawl over `PayloadType`, every payload type is
/// routed through this one data-driven table. A handler decides *how* a
/// payload is transformed; the actual work lives in dedicated transformers.
///
/// Anything not listed here falls through to the legacy-wrap classifier
/// (stage 2e) — nothing is ever silently dropped.
public enum PayloadHandler: Equatable {
    /// The `com.apple.applicationaccess` split (stage 2d).
    case fanOut
    /// The `com.apple.ManagedClient.preferences` MCX unwrap (stage 2c).
    case mcx
    /// A clean 1:1 mapping to a single DDM domain, copying the listed keys.
    /// `keys == nil` means "copy the whole payload body (minus Payload* meta)".
    case direct(domain: String, keys: [String]?)
    /// Known to have no declarative equivalent — wrap as legacy with a reason.
    case knownLegacy(reason: String)
}

public enum MappingTable {
    /// PayloadType → handler. The audit surface for "what does the engine do
    /// with each payload type". Extend as Apple ships more declarative configs.
    public static let handlers: [String: PayloadHandler] = [
        "com.apple.applicationaccess": .fanOut,
        "com.apple.ManagedClient.preferences": .mcx,

        // Examples of payloads that remain legacy in the macOS 27 cycle. Listed
        // explicitly (rather than relying on the default) so the report can
        // give a precise reason instead of a generic one.
        "com.apple.security.pkcs1": .knownLegacy(
            reason: "Certificate payloads are delivered via asset declarations / legacy profile; no inline declarative equivalent."),
        "com.apple.wifi.managed": .knownLegacy(
            reason: "Wi-Fi configuration has no declarative equivalent in the macOS 27 cycle; preserved via com.apple.configuration.legacy."),
        "com.apple.vpn.managed": .knownLegacy(
            reason: "VPN configuration has no declarative equivalent in the macOS 27 cycle; preserved via com.apple.configuration.legacy."),
    ]

    /// The default for any unlisted payload type.
    public static let defaultLegacyReason =
        "No DDM equivalent in the macOS 27 declaration set (per this mapping table); preserved verbatim via com.apple.configuration.legacy."

    public static func handler(for payloadType: String) -> PayloadHandler {
        handlers[payloadType] ?? .knownLegacy(reason: defaultLegacyReason)
    }
}
