import Foundation

/// Stage 2d — the `com.apple.applicationaccess` fan-out (the centerpiece).
///
/// `com.apple.applicationaccess` does NOT map 1:1. In the macOS 26.4 cycle a
/// family of restriction keys covering Apple Intelligence, Siri, and the
/// keyboard were **deprecated in the legacy restrictions payload and moved
/// into dedicated declarative configurations**. So migrating this payload is a
/// *split*, not a key-by-key rename: depending on which keys are present, one
/// source payload can produce up to four separate DDM declarations — plus a
/// legacy wrap for any residual restriction keys that still have no
/// declarative home (e.g. `allowCamera`).
///
/// The routing lives in one auditable table below. Each row is a single
/// (legacy key → DDM domain → declarative key) decision an admin can review.
///
/// ─────────────────────────────────────────────────────────────────────────
/// CLEAN-ROOM NOTE: domain strings are taken from Apple's public DDM /
/// Platform Deployment documentation for the macOS 27 cycle. The *target key*
/// names (right-hand column) are a best-effort mapping and the single place to
/// adjust as Apple finalizes the declarative schemas. Value **semantics** are
/// passed through unchanged; where a legacy `allow…`/`force…` boolean may need
/// re-interpretation under the declarative schema, the migration report flags
/// it for review rather than guessing.
/// ─────────────────────────────────────────────────────────────────────────
public enum FanOutTable {

    /// The four DDM domains an `applicationaccess` payload can fan out into.
    public enum Domain: String, CaseIterable {
        case intelligence = "com.apple.configuration.intelligence.settings"
        case externalIntelligence = "com.apple.configuration.external-intelligence.settings"
        case siri = "com.apple.configuration.siri.settings"
        case keyboard = "com.apple.configuration.keyboard.settings"
    }

    /// One row of the routing table.
    public struct Route {
        /// The key as it appears in the legacy restrictions payload.
        public let legacyKey: String
        /// The DDM configuration domain it now belongs to.
        public let domain: Domain
        /// The key name to use inside that declaration's payload.
        public let targetKey: String
        /// If true, the report flags this key's value semantics for review
        /// (e.g. a `force…` toggle whose polarity may differ declaratively).
        public let reviewValueSemantics: Bool

        public init(_ legacyKey: String, _ domain: Domain, _ targetKey: String,
                    reviewValueSemantics: Bool = false) {
            self.legacyKey = legacyKey
            self.domain = domain
            self.targetKey = targetKey
            self.reviewValueSemantics = reviewValueSemantics
        }
    }

    /// THE routing table. Add rows here as Apple's schemas firm up.
    public static let routes: [Route] = [
        // ── Apple Intelligence → com.apple.configuration.intelligence.settings
        Route("allowGenmoji",                 .intelligence, "allowGenmoji"),
        Route("allowImagePlayground",         .intelligence, "allowImagePlayground"),
        Route("allowImageWand",               .intelligence, "allowImageWand"),
        Route("allowWritingTools",            .intelligence, "allowWritingTools"),
        Route("allowMailSummary",             .intelligence, "allowMailSummary"),
        Route("allowMailSmartReplies",        .intelligence, "allowMailSmartReplies"),
        Route("allowNotesTranscription",      .intelligence, "allowNotesTranscription"),
        Route("allowSafariSummary",           .intelligence, "allowSafariSummary"),

        // ── External intelligence (e.g. ChatGPT extension) →
        //    com.apple.configuration.external-intelligence.settings
        Route("allowExternalIntelligenceIntegrations",
              .externalIntelligence, "allowIntegrations"),
        Route("allowExternalIntelligenceIntegrationsSignIn",
              .externalIntelligence, "allowIntegrationsSignIn"),

        // ── Siri → com.apple.configuration.siri.settings
        Route("allowAssistant",                    .siri, "allowAssistant"),
        Route("allowAssistantWhileLocked",         .siri, "allowAssistantWhileLocked"),
        Route("allowAssistantUserGeneratedContent",.siri, "allowUserGeneratedContent"),
        Route("forceAssistantProfanityFilter",     .siri, "forceProfanityFilter",
              reviewValueSemantics: true),

        // ── Keyboard / dictation → com.apple.configuration.keyboard.settings
        Route("allowDictation",          .keyboard, "allowDictation"),
        Route("allowPredictiveKeyboard", .keyboard, "allowPredictiveText"),
        Route("allowAutoCorrection",     .keyboard, "allowAutoCorrection"),
        Route("allowSpellCheck",         .keyboard, "allowSpellCheck"),
        Route("allowKeyboardShortcuts",  .keyboard, "allowKeyboardShortcuts"),
    ]

    /// Fast lookup: legacy key → route.
    public static let routesByLegacyKey: [String: Route] = {
        var map: [String: Route] = [:]
        for r in routes { map[r.legacyKey] = r }
        return map
    }()
}
