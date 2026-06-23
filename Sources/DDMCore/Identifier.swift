import Foundation
import CryptoKit

/// Deterministic identifiers for produced declarations.
///
/// DDM declarations need a stable `Identifier`. We derive it from the source
/// profile + payload + target domain so that re-running the migrator on the
/// same input yields byte-identical output (clean diffs, reproducible tests)
/// instead of a fresh random UUID each run.
enum IdentifierFactory {
    /// e.g. `com.apple.configuration.siri.settings.a1b2c3d4`
    static func make(domain: String, profileID: String?, sourceIndex: Int, salt: String = "") -> String {
        let seed = "\(profileID ?? "no-profile-id")|\(sourceIndex)|\(domain)|\(salt)"
        let digest = SHA256.hash(data: Data(seed.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return "\(domain).\(hex.prefix(8))"
    }
}
