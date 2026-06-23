import Foundation

/// Generates a vendor-agnostic deployment guide (`DEPLOYMENT.md`) on export.
///
/// DDM Migrator's output is standard Apple declaration JSON — Type / Identifier
/// / Payload — so it isn't tied to any one MDM. But every MDM ingests custom
/// declarations differently (and some don't yet), so the guide spells out the
/// workflow per vendor and is honest about current limitations.
///
/// Two ingestion shapes matter:
///   • whole-file  — the vendor takes the full `.ddm.json` (e.g. Fleet).
///   • paste       — the vendor wants the declaration Type plus the *Payload
///                   object only*, and generates its own Identifier/ServerToken
///                   (e.g. Jamf Pro Blueprints → Custom Declarations).
public enum DeploymentGuide {

    public static func markdown(report: MigrationReport) -> String {
        let types = Set(report.allPayloads.flatMap { $0.producedDeclarations.map { $0.type } })
            .sorted()

        var md = "# Deploying these declarations\n\n"
        md += "_Generated \(report.generatedAtISO8601)_\n\n"
        md += "DDM Migrator emits **standard Apple declaration JSON** (`Type` / `Identifier` / "
        md += "`Payload`) in the `*.ddm.json` files. That format is vendor-neutral — how you get it "
        md += "onto devices depends on your MDM. This guide covers the common ones.\n\n"

        if !types.isEmpty {
            md += "**Declaration types produced in this export:**\n\n"
            for t in types { md += "- `\(t)`\n" }
            md += "\n"
        }

        md += "## Two shapes you'll need\n\n"
        md += "- **Whole-file** — some MDMs take the entire `.ddm.json` as-is.\n"
        md += "- **Paste (Type + Payload)** — some MDMs ask for the declaration *Type* and the "
        md += "**contents of the `Payload` object only**, and generate the `Identifier`/`ServerToken` "
        md += "themselves. In that case, open the `.ddm.json` and copy the value of the top-level "
        md += "`Payload` key (not the whole file).\n\n"

        md += "## Vendor support\n\n"
        md += "| MDM | Import custom DDM JSON? | How |\n"
        md += "|---|---|---|\n"
        md += "| **FleetDM** | ✅ Yes | Whole-file. Upload the `.ddm.json` under **Controls → OS settings**, or commit it to your Fleet **GitOps** repo (`apple_settings.configuration_profiles` accepts `.json` declarations). |\n"
        md += "| **Jamf Pro** | ✅ Yes (Blueprints) | Paste. **Blueprints → Custom Declarations → Add item**: set **Kind** = Configuration, **Channel** = System (or User), **Type** = the declaration's `Type`, **Payload** = the contents of its `Payload` object (use the `.payload.json` companion file). Jamf generates the Identifier/ServerToken. (API deploy is \"coming soon\" per Jamf.) |\n"
        md += "| **Kandji (now Iru)** | ⚠️ Not directly | Kandji — rebranded **Iru** in late 2025 — delivers DDM through its own **Library items / policies**; no documented import for arbitrary custom declaration JSON. Use these files as the source of truth and configure the matching settings in Kandji/Iru. |\n"
        md += "| **Addigy** | ⚠️ Not directly | Addigy delivers DDM through its **policies** (today focused on OS updates); there's no documented import for arbitrary custom declaration JSON yet. Use these files as the source of truth and map the settings into Addigy policies. |\n"
        md += "| **Mosyle** | ⚠️ Not directly | Like Addigy — DDM is surfaced through Mosyle's policy UI; no documented custom-JSON import. Use these files as reference when configuring policies. |\n"
        md += "| **Intune** | ❌ Not yet | Intune only exposes specific Microsoft-surfaced declarations (**Settings Catalog → DDM**, mainly software updates). Arbitrary custom DDM JSON cannot be imported today. |\n\n"
        md += "_For the ⚠️/❌ vendors the declarations are still useful: they're the exact, audited "
        md += "settings to reproduce in that MDM's UI, and they're ready to import the moment the "
        md += "vendor adds custom-declaration support._\n\n"

        md += "## Notes\n\n"
        md += "- **Channel:** these configurations are typically delivered on the **System (device)** "
        md += "channel; verify per declaration for your environment.\n"
        md += "- **Identifiers:** the `Identifier` in each file is deterministic (derived from the "
        md += "source profile) so re-runs diff cleanly. Paste-based MDMs ignore it and assign their own.\n"
        md += "- **Legacy wraps:** `com.apple.configuration.legacy` references the original profile via "
        md += "a `ProfileURL` placeholder (`\(LegacyWrap.profileURLPlaceholder)`). Host the original "
        md += "`.mobileconfig` and replace the placeholder, or simply keep delivering the original "
        md += "profile alongside your declarations.\n"
        md += "- **Flagged payloads:** anything marked ⚠️ in `migration-report.md` needs manual review "
        md += "before deployment — it wasn't auto-converted.\n\n"

        md += "> Scope: DDM Migrator transforms files. It does not push to any MDM or verify that "
        md += "declarations land on devices — you bring the output into your MDM's own workflow above.\n"
        return md
    }
}
