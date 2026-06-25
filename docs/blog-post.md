# DDM Migrator: turn your legacy `.mobileconfig` profiles into DDM declarations

_A free, open-source (MIT) macOS app from Machinery Software._

If you manage Macs, you already feel the ground shifting under configuration
profiles. Apple has spent the last few release cycles moving settings out of the
old MDM profile world and into **Declarative Device Management (DDM)** — and the
macOS 26.4 cycle made it concrete: a whole family of Apple Intelligence, Siri,
and keyboard restriction keys were **deprecated in the legacy restrictions
payload and moved into dedicated declarative configurations.**

That's not a "flip a switch" change. Your existing `.mobileconfig` library
doesn't translate one-to-one into declarations — and the gnarliest payload of
all, `com.apple.applicationaccess`, doesn't translate at all in the naive sense.
So we built a tool to do the translation honestly, show its work, and never
silently drop a setting.

Meet **DDM Migrator**.

![DDM Migrator — results table](screenshot-results.png)

## What it does

Drag in one or many `.mobileconfig` files (or a whole folder). DDM Migrator reads
each profile and converts every payload into the equivalent DDM `*.ddm.json`
declarations — plus a migration report that explains, payload by payload, exactly
what it did and why.

- **It reads signed profiles.** Jamf and others export profiles wrapped in a
  CMS/PKCS7 signature envelope — the bytes on disk aren't a plist at all. DDM
  Migrator strips the envelope natively via the Security framework's `CMSDecoder`
  (no `openssl` shell-out), and handles plain unsigned profiles too.
- **It routes every payload** through a data-driven mapping table — no
  `if/else` sprawl, one auditable place that decides each payload's fate.
- **It never silently drops anything.** Payloads with no declarative equivalent
  are preserved verbatim and wrapped as `com.apple.configuration.legacy`, with
  the reason recorded in the report.

## The interesting part: `applicationaccess` is a *split*, not a rename

Here's the nugget that makes this more than a find-and-replace. When those
Intelligence/Siri/keyboard keys were deprecated, they didn't just get renamed —
they moved to **four different declarative configuration domains**. So a single
`com.apple.applicationaccess` restrictions payload fans out into up to four
separate declarations:

- `com.apple.configuration.intelligence.settings` — Genmoji, Image Playground,
  Writing Tools, Image Wand, Mail/Notes/Safari intelligence
- `com.apple.configuration.external-intelligence.settings` — external
  integrations + sign-in
- `com.apple.configuration.siri.settings` — Siri allow/lock/UGC/profanity
- `com.apple.configuration.keyboard.settings` — dictation, predictive text,
  autocorrect, spellcheck

…and any *residual* restriction keys that still have no declarative home (think
`allowCamera`) are preserved as a legacy wrap. One payload in, several
declarations out:

![One applicationaccess payload fanning out to all four DDM domains](screenshot-all-domains.png)

The key→domain routing lives in one table you can read and extend in a single
file. That's deliberate: as Apple finalizes the schemas, the audit surface is one
place, not a thousand lines of branching.

There's similar care elsewhere — **MCX** (`com.apple.ManagedClient.preferences`)
payloads get unwrapped from their nested `Forced[0].mcx_preference_settings`
structure, and anything that deviates (a `Set-Once` state, an unexpected index)
is **flagged for review rather than guessed at**.

## The migration report is the point

Any tool can emit JSON. The reason to trust one is that it tells you what it did.
Every run classifies each payload as migrated / fanned-out / legacy-wrapped /
flagged, with a reason for each, plus an edge-case list at the end. That report
(`migration-report.md` + a JSON twin) is what lets you hand a migration to a
colleague — or a future you — with confidence.

## It's vendor-agnostic

The output is **standard Apple declaration JSON**, not tied to any one MDM. But
every MDM ingests custom declarations differently — and some don't yet — so each
export also drops a `DEPLOYMENT.md` with per-vendor steps:

| MDM | Import custom DDM JSON today? |
|---|---|
| **FleetDM** | ✅ Yes — `.json` upload (UI or GitOps) |
| **Jamf Pro** | ✅ Yes — Blueprints → Custom Declarations |
| **Kandji (now Iru)** | ⚠️ Via its own policies; no custom-JSON import |
| **Addigy** | ⚠️ Via policies; no custom-JSON import |
| **Mosyle** | ⚠️ Via policy UI; no custom-JSON import |
| **Intune** | ❌ Only Microsoft-surfaced declarations |

For Fleet we generate a ready-to-merge `fleet-gitops.yml`; for Jamf we also write
a `.payload.json` companion (Jamf Blueprints wants the Payload object, not the
whole envelope). For the ⚠️/❌ vendors the declarations are still the exact,
audited settings to reproduce — and they're ready to import the moment those
vendors add support.

## A CLI for the pipeline people

The same engine ships as a headless `ddm-migrate` CLI, so you can wire it into CI
or a script:

```sh
ddm-migrate profiles/ -o out/
```

It writes the same declarations, reports, and deployment snippets as the app.

There's also **experimental, opt-in API push** to the two MDMs that support it
today — FleetDM and Jamf (the latter via the Platform API Blueprints endpoint,
with the OAuth2 client-credentials exchange handled for you). It's deliberately
**feature-flagged off** (`DDM_ENABLE_PUSH=1`) until you've validated it against a
sandbox; the `--*-dry-run` previews always work and make no network calls. Tokens
come only from environment variables — never flags, never logged.

## The scope boundary (on purpose)

DDM Migrator transforms **files**: input is `.mobileconfig`, output is
`.ddm.json` plus a report. By default it doesn't touch your MDM and never claims a
declaration landed on a device — you bring the output into your own workflow. That
firm boundary is exactly what makes it useful and trustworthy today, rather than a
half-working push-to-everything tool.

## Clean-room and open

DDM Migrator was built clean-room from public Apple Developer documentation. It
contains no employer-internal code, profile values, tenant identifiers, tokens,
or configuration. Every test fixture is synthetic. It's MIT-licensed, the engine
and UI are cleanly separated, and the whole thing is on GitHub.

**Contributions welcome** — especially new payload mappings and fan-out routing
as Apple's schemas firm up.

👉 **[github.com/mactesting12/ddm-migrator](https://github.com/mactesting12/ddm-migrator)**

---

_Built with SwiftUI for macOS 14+. Drop a profile in and see what your DDM
migration actually looks like._
