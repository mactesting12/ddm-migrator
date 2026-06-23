import Foundation

/// The per-payload transformers. Each takes one source payload dictionary and
/// returns one or more `PayloadResult`s. They never throw on odd input — a
/// payload that can't be transformed becomes a legacy wrap or a flagged result,
/// so the engine degrades gracefully and never drops data.
enum Transformers {

    /// Keys that are profile bookkeeping, not real settings. Stripped before a
    /// payload body is copied into a declaration.
    static let payloadMetaKeys: Set<String> = [
        "PayloadType", "PayloadVersion", "PayloadIdentifier", "PayloadUUID",
        "PayloadDisplayName", "PayloadDescription", "PayloadOrganization",
        "PayloadEnabled",
    ]

    // MARK: 2d — applicationaccess fan-out

    /// Split a `com.apple.applicationaccess` payload across its DDM domains,
    /// plus a legacy wrap for any residual restriction keys with no home.
    static func fanOutApplicationAccess(payload: [String: Any],
                                        sourceIndex: Int,
                                        profileID: String?) -> [PayloadResult] {
        let displayName = payload["PayloadDisplayName"] as? String
        var byDomain: [FanOutTable.Domain: [String: JSONValue]] = [:]
        var reviewKeysByDomain: [FanOutTable.Domain: [String]] = [:]
        var residual: [String: Any] = [:]

        for (key, value) in payload {
            if payloadMetaKeys.contains(key) { continue }
            if let route = FanOutTable.routesByLegacyKey[key] {
                let (jv, _) = JSONValue.fromPlist(value)
                byDomain[route.domain, default: [:]][route.targetKey] = jv
                if route.reviewValueSemantics {
                    reviewKeysByDomain[route.domain, default: []].append(route.targetKey)
                }
            } else {
                residual[key] = value
            }
        }

        var results: [PayloadResult] = []

        // One declaration per domain that matched at least one key. Emit in a
        // stable order so output is deterministic.
        for domain in FanOutTable.Domain.allCases {
            guard let body = byDomain[domain], !body.isEmpty else { continue }
            let identifier = IdentifierFactory.make(
                domain: domain.rawValue, profileID: profileID, sourceIndex: sourceIndex)
            let decl = Declaration(type: domain.rawValue,
                                   identifier: identifier,
                                   payload: .object(body))
            var reason = "Fanned out from com.apple.applicationaccess: \(body.count) key(s) routed to \(domain.rawValue) (deprecated in the 26.4 cycle and moved to this declarative configuration)."
            if let review = reviewKeysByDomain[domain], !review.isEmpty {
                reason += " Review value semantics for: \(review.sorted().joined(separator: ", "))."
            }
            results.append(PayloadResult(
                sourceType: "com.apple.applicationaccess",
                sourceIndex: sourceIndex,
                sourceDisplayName: displayName,
                classification: .fannedOut,
                targetDomains: [domain.rawValue],
                reason: reason,
                producedDeclarations: [decl]))
        }

        // Residual restriction keys (e.g. allowCamera) stay legacy.
        if !residual.isEmpty {
            // Rebuild a minimal restrictions payload carrying only the residual
            // keys, preserved verbatim.
            var preserved = residual
            preserved["PayloadType"] = "com.apple.applicationaccess"
            let (preservedJV, _) = JSONValue.fromPlist(preserved)
            let legacy = makeLegacyDeclaration(
                preserved: preservedJV, profileID: profileID,
                sourceIndex: sourceIndex, salt: "residual")
            let keyList = residual.keys.sorted().joined(separator: ", ")
            results.append(PayloadResult(
                sourceType: "com.apple.applicationaccess",
                sourceIndex: sourceIndex,
                sourceDisplayName: displayName,
                classification: .legacyWrapped,
                targetDomains: [LegacyWrap.legacyDomain],
                reason: "Residual restriction key(s) with no declarative equivalent kept as a legacy wrap: \(keyList).",
                producedDeclarations: [legacy],
                preservedSource: preservedJV))
        }

        // Pathological: a payload with only meta keys and nothing routable.
        if results.isEmpty {
            results.append(PayloadResult(
                sourceType: "com.apple.applicationaccess",
                sourceIndex: sourceIndex,
                sourceDisplayName: displayName,
                classification: .flagged,
                targetDomains: [],
                reason: "applicationaccess payload contained no recognised restriction keys.",
                producedDeclarations: []))
        }

        return results
    }

    // MARK: 2c — MCX unwrap

    /// Unwrap a `com.apple.ManagedClient.preferences` (MCX) payload.
    ///
    /// Settings are nested as:
    ///   payload["PayloadContent"][<domain>]["Forced"][0]["mcx_preference_settings"]
    ///
    /// ASSUMPTION (documented): we read the `Forced` state at index 0. If a
    /// domain instead uses `Set-Once`/`Set-Always`, or has a `Forced` array
    /// with more/zero entries than expected, we do NOT guess — that domain is
    /// flagged as unsupported (and surfaced), never dropped or crashed on.
    static func unwrapMCX(payload: [String: Any],
                          sourceIndex: Int,
                          profileID: String?) -> [PayloadResult] {
        let displayName = payload["PayloadDisplayName"] as? String
        guard let content = payload["PayloadContent"] as? [String: Any], !content.isEmpty else {
            // Nothing to unwrap — preserve verbatim as legacy.
            let (jv, _) = JSONValue.fromPlist(payload)
            let legacy = makeLegacyDeclaration(
                preserved: jv, profileID: profileID, sourceIndex: sourceIndex, salt: "mcx")
            return [PayloadResult(
                sourceType: "com.apple.ManagedClient.preferences",
                sourceIndex: sourceIndex,
                sourceDisplayName: displayName,
                classification: .legacyWrapped,
                targetDomains: [LegacyWrap.legacyDomain],
                reason: "MCX payload had no PayloadContent domains; preserved verbatim as legacy.",
                producedDeclarations: [legacy],
                preservedSource: jv)]
        }

        var results: [PayloadResult] = []

        for (domain, rawDomainValue) in content.sorted(by: { $0.key < $1.key }) {
            guard let domainDict = rawDomainValue as? [String: Any] else {
                results.append(flaggedMCX(domain: domain, sourceIndex: sourceIndex,
                                          displayName: displayName,
                                          why: "domain value was not a dictionary"))
                continue
            }

            // Locate the settings, handling the documented Forced[0] case and
            // flagging anything that deviates.
            guard let forced = domainDict["Forced"] as? [Any] else {
                let state = domainDict.keys.filter { $0 != "Forced" }.sorted().joined(separator: ", ")
                results.append(flaggedMCX(
                    domain: domain, sourceIndex: sourceIndex, displayName: displayName,
                    why: "no 'Forced' management state (found: \(state.isEmpty ? "none" : state)); Set-Once/Set-Always are not auto-migrated"))
                continue
            }
            guard let first = forced.first as? [String: Any] else {
                results.append(flaggedMCX(domain: domain, sourceIndex: sourceIndex,
                                          displayName: displayName,
                                          why: "'Forced' array was empty"))
                continue
            }
            if forced.count > 1 {
                results.append(flaggedMCX(
                    domain: domain, sourceIndex: sourceIndex, displayName: displayName,
                    why: "'Forced' had \(forced.count) entries; only index 0 is auto-migrated, the rest need manual review"))
                // fall through and still migrate index 0 below
            }
            guard let settings = first["mcx_preference_settings"] as? [String: Any], !settings.isEmpty else {
                results.append(flaggedMCX(domain: domain, sourceIndex: sourceIndex,
                                          displayName: displayName,
                                          why: "Forced[0] had no 'mcx_preference_settings'"))
                continue
            }

            // MCX managed-preference domains have no generic DDM equivalent;
            // the sanctioned path is a legacy wrap that carries the unwrapped
            // settings for the named preference domain.
            var preserved: [String: Any] = [
                "PreferenceDomain": domain,
                "Settings": settings,
            ]
            preserved["PayloadType"] = "com.apple.ManagedClient.preferences"
            let (jv, _) = JSONValue.fromPlist(preserved)
            let legacy = makeLegacyDeclaration(
                preserved: jv, profileID: profileID,
                sourceIndex: sourceIndex, salt: "mcx-\(domain)")
            results.append(PayloadResult(
                sourceType: "com.apple.ManagedClient.preferences",
                sourceIndex: sourceIndex,
                sourceDisplayName: displayName,
                classification: .legacyWrapped,
                targetDomains: [LegacyWrap.legacyDomain],
                reason: "Unwrapped MCX managed-preference domain '\(domain)' (\(settings.count) setting(s)) from Forced[0]; preserved as legacy (no generic declarative equivalent for arbitrary preference domains).",
                producedDeclarations: [legacy],
                preservedSource: jv))
        }

        if results.isEmpty {
            results.append(flaggedMCX(domain: "(all)", sourceIndex: sourceIndex,
                                      displayName: displayName,
                                      why: "no migratable preference domains found"))
        }
        return results
    }

    private static func flaggedMCX(domain: String, sourceIndex: Int,
                                   displayName: String?, why: String) -> PayloadResult {
        PayloadResult(
            sourceType: "com.apple.ManagedClient.preferences",
            sourceIndex: sourceIndex,
            sourceDisplayName: displayName,
            classification: .flagged,
            targetDomains: [],
            reason: "MCX domain '\(domain)' not auto-migrated: \(why). Surfaced for manual handling — not dropped.",
            producedDeclarations: [])
    }

    // MARK: 2b/direct — clean 1:1 mapping

    static func direct(domain: String, keys: [String]?, payload: [String: Any],
                       sourceIndex: Int, profileID: String?) -> [PayloadResult] {
        let displayName = payload["PayloadDisplayName"] as? String
        var body: [String: JSONValue] = [:]
        for (k, v) in payload {
            if payloadMetaKeys.contains(k) { continue }
            if let keys, !keys.contains(k) { continue }
            body[k] = JSONValue.fromPlist(v).value
        }
        let identifier = IdentifierFactory.make(
            domain: domain, profileID: profileID, sourceIndex: sourceIndex)
        let decl = Declaration(type: domain, identifier: identifier, payload: .object(body))
        return [PayloadResult(
            sourceType: payload["PayloadType"] as? String ?? "(unknown)",
            sourceIndex: sourceIndex,
            sourceDisplayName: displayName,
            classification: .migrated,
            targetDomains: [domain],
            reason: "Mapped 1:1 to \(domain) (\(body.count) key(s)).",
            producedDeclarations: [decl])]
    }

    // MARK: shared legacy declaration builder

    static func makeLegacyDeclaration(preserved: JSONValue, profileID: String?,
                                      sourceIndex: Int, salt: String) -> Declaration {
        LegacyWrap.declaration(preserved: preserved, profileID: profileID,
                               sourceIndex: sourceIndex, salt: salt)
    }
}
