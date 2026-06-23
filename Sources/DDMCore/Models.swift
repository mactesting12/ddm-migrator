import Foundation

// MARK: - Public result model
//
// These types are the contract between the DDMCore engine and any front end
// (the SwiftUI app today, a CLI tomorrow). They are deliberately UI-free.

/// How a single source payload ended up being treated by the engine.
public enum Classification: String, Codable, Sendable {
    /// Mapped cleanly to one DDM configuration domain.
    case migrated
    /// One source payload split across multiple DDM domains
    /// (the `com.apple.applicationaccess` centerpiece).
    case fannedOut
    /// No native DDM equivalent — preserved verbatim inside a
    /// `com.apple.configuration.legacy` declaration.
    case legacyWrapped
    /// Recognised but the structure deviated from what we can safely
    /// transform (e.g. an MCX Set-Once domain). Surfaced, never dropped.
    case flagged

    public var symbol: String {
        switch self {
        case .migrated: return "✅"
        case .fannedOut: return "🔀"
        case .legacyWrapped: return "📦"
        case .flagged: return "⚠️"
        }
    }
}

/// The shape of the input file before decoding.
public enum SourceFormat: String, Codable, Sendable {
    /// A bare XML/binary plist — `.mobileconfig` that was never signed.
    case rawPlist
    /// A CMS/PKCS7-wrapped profile (the common Jamf export shape).
    case cmsSigned
}

/// A single DDM declaration ready to be written to disk as `*.ddm.json`.
public struct Declaration: Codable, Sendable, Equatable {
    /// e.g. `com.apple.configuration.siri.settings`
    public let type: String
    /// Stable, content-derived identifier (reproducible across runs).
    public let identifier: String
    /// The declaration body. Stored normalised (JSON-safe) so it round-trips.
    public let payload: JSONValue

    public init(type: String, identifier: String, payload: JSONValue) {
        self.type = type
        self.identifier = identifier
        self.payload = payload
    }

    /// Apple declaration envelope: `Type` / `Identifier` / `Payload`.
    public func envelope() -> JSONValue {
        .object([
            "Type": .string(type),
            "Identifier": .string(identifier),
            "Payload": payload,
        ])
    }

    /// Pretty-printed JSON bytes for the declaration file.
    public func jsonData() throws -> Data {
        try envelope().prettyPrintedData()
    }

    /// A filesystem-friendly file name for this declaration.
    public func suggestedFileName() -> String {
        // com.apple.configuration.siri.settings -> siri.settings.ddm.json
        let short = type
            .replacingOccurrences(of: "com.apple.configuration.", with: "")
            .replacingOccurrences(of: "com.apple.", with: "")
        let shortID = String(identifier.suffix(8))
        return "\(short).\(shortID).ddm.json"
    }
}

/// The outcome for one source payload (or one fan-out branch of one payload).
public struct PayloadResult: Codable, Sendable, Identifiable {
    public var id: String { "\(sourceIndex)-\(sourceType)-\(targetDomains.joined(separator: ","))-\(classification.rawValue)" }

    /// `PayloadType` from the source profile.
    public let sourceType: String
    /// Index within the source `PayloadContent` array (for grouping in the UI).
    public let sourceIndex: Int
    /// Source payload's `PayloadDisplayName`, if present.
    public let sourceDisplayName: String?
    public let classification: Classification
    /// DDM domains this branch produced (empty for a pure legacy wrap).
    public let targetDomains: [String]
    /// Human-readable explanation — the audit trail line.
    public let reason: String
    public let producedDeclarations: [Declaration]
    /// For legacy wraps: the original payload content, preserved verbatim so
    /// an admin can host/reference it. Kept out of the produced declaration
    /// JSON (which stays standards-shaped) but available to the report, the
    /// UI preview, and the optional `.preserved.plist` export.
    public let preservedSource: JSONValue?

    public init(sourceType: String,
                sourceIndex: Int,
                sourceDisplayName: String?,
                classification: Classification,
                targetDomains: [String],
                reason: String,
                producedDeclarations: [Declaration],
                preservedSource: JSONValue? = nil) {
        self.sourceType = sourceType
        self.sourceIndex = sourceIndex
        self.sourceDisplayName = sourceDisplayName
        self.classification = classification
        self.targetDomains = targetDomains
        self.reason = reason
        self.producedDeclarations = producedDeclarations
        self.preservedSource = preservedSource
    }
}

/// Top-level status of one input profile (drives the row colour in the UI).
public enum ProfileStatus: String, Codable, Sendable {
    case migrated      // everything mapped cleanly / fanned out
    case partial       // a mix — at least one legacy wrap or flag
    case legacyWrap    // nothing had a DDM equivalent
    case error         // file couldn't be read / decoded / parsed

    public var symbol: String {
        switch self {
        case .migrated: return "✅"
        case .partial: return "⚠️"
        case .legacyWrap: return "📦"
        case .error: return "⛔️"
        }
    }
}

/// The full result for one input `.mobileconfig`.
public struct ProfileResult: Codable, Sendable, Identifiable {
    public var id: String { fileName }

    public let fileName: String
    public let sourceFormat: SourceFormat?
    public let profileIdentifier: String?
    public let profileDisplayName: String?
    public let payloads: [PayloadResult]
    /// File-level failure (unreadable, not a profile, CMS decode failed).
    public let error: String?

    public init(fileName: String,
                sourceFormat: SourceFormat?,
                profileIdentifier: String?,
                profileDisplayName: String?,
                payloads: [PayloadResult],
                error: String?) {
        self.fileName = fileName
        self.sourceFormat = sourceFormat
        self.profileIdentifier = profileIdentifier
        self.profileDisplayName = profileDisplayName
        self.payloads = payloads
        self.error = error
    }

    /// Number of payloads in the source `PayloadContent` (distinct source rows).
    public var sourcePayloadCount: Int {
        Set(payloads.map { $0.sourceIndex }).count
    }

    /// Total DDM declarations produced across all payloads.
    public var declarationCount: Int {
        payloads.reduce(0) { $0 + $1.producedDeclarations.count }
    }

    public var status: ProfileStatus {
        if error != nil { return .error }
        if payloads.isEmpty { return .error }
        let hasLegacy = payloads.contains { $0.classification == .legacyWrapped }
        let hasFlag = payloads.contains { $0.classification == .flagged }
        let allLegacy = payloads.allSatisfy { $0.classification == .legacyWrapped }
        if allLegacy { return .legacyWrap }
        if hasLegacy || hasFlag { return .partial }
        return .migrated
    }
}
