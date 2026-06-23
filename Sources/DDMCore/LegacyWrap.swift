import Foundation

/// Stage 2e — the legacy-wrap classifier.
///
/// Any payload with no native DDM equivalent is preserved verbatim and mapped
/// to Apple's sanctioned `com.apple.configuration.legacy`, which references the
/// original profile via the ProfileAssetReference mechanism. Nothing is ever
/// silently dropped; the report records *why* each payload stayed legacy.
///
/// The produced declaration is kept standards-shaped (a `ProfileURL` the admin
/// fills in once they host the original `.mobileconfig`, plus a deterministic
/// `ProfileAssetReference` identifier). The original payload content itself is
/// carried on `PayloadResult.preservedSource` (and can be exported as a
/// companion `.preserved.plist`) so the bytes are never lost — but it stays out
/// of the declaration JSON so that file remains deploy-ready.
public enum LegacyWrap {
    public static let legacyDomain = "com.apple.configuration.legacy"
    public static let assetDomain = "com.apple.asset.profile"

    /// Placeholder the admin must replace with the hosted profile URL. Made
    /// loud on purpose so it can never be deployed by accident.
    public static let profileURLPlaceholder =
        "REPLACE_ME://host-the-original-.mobileconfig-and-put-its-https-url-here"

    static func declaration(preserved: JSONValue, profileID: String?,
                            sourceIndex: Int, salt: String) -> Declaration {
        let assetID = IdentifierFactory.make(
            domain: assetDomain, profileID: profileID, sourceIndex: sourceIndex, salt: salt)
        let configID = IdentifierFactory.make(
            domain: legacyDomain, profileID: profileID, sourceIndex: sourceIndex, salt: salt)
        let payload: JSONValue = .object([
            "ProfileURL": .string(profileURLPlaceholder),
            "ProfileAssetReference": .string(assetID),
        ])
        return Declaration(type: legacyDomain, identifier: configID, payload: payload)
    }
}
