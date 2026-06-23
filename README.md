# DDM Migrator

[![CI](https://github.com/mactesting12/ddm-migrator/actions/workflows/ci.yml/badge.svg)](https://github.com/mactesting12/ddm-migrator/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue.svg)](#requirements)

**Migrate legacy `.mobileconfig` configuration profiles into Declarative Device Management (DDM) declarations for macOS 27.**

DDM Migrator is a small, native macOS app for Mac admins. Drop in your old MDM
configuration profiles and it converts each payload into the equivalent DDM
`*.ddm.json` declarations — and gives you a migration report that explains, payload
by payload, exactly what it did and why.

> _A [Machinery Software](https://github.com/mactesting12) project._

![DDM Migrator screenshot placeholder](docs/screenshot.png)

> 📸 _Screenshot placeholder — drop a real screenshot at `docs/screenshot.png`._

---

## What it does

Drag in one or many `.mobileconfig` files (or a folder) and DDM Migrator:

- **Strips CMS/PKCS7 signatures** — Jamf and others export signed profiles. DDM
  Migrator decodes the envelope natively (Security framework `CMSDecoder`, no
  `openssl` shell-out) and also handles plain unsigned profiles.
- **Walks every payload** through a data-driven mapping table — no `if/else` sprawl.
- **Fans out `com.apple.applicationaccess`** — the centerpiece. In the macOS 26.4
  cycle, Apple Intelligence, Siri, and keyboard restriction keys were deprecated in
  the legacy restrictions payload and moved to dedicated declarative configurations.
  So one restrictions payload **splits** across up to four domains:
  - `com.apple.configuration.intelligence.settings`
  - `com.apple.configuration.external-intelligence.settings`
  - `com.apple.configuration.siri.settings`
  - `com.apple.configuration.keyboard.settings`
- **Unwraps MCX** (`com.apple.ManagedClient.preferences`) — pulls settings out of
  the nested `Forced[0].mcx_preference_settings` structure, per preference domain.
- **Never silently drops anything.** Payloads with no declarative equivalent are
  preserved verbatim and wrapped as `com.apple.configuration.legacy` (referencing
  the profile via the `ProfileAssetReference` mechanism), with the reason recorded.
- **Writes a migration report** (`migration-report.md` + `.json`) classifying every
  payload as migrated / fanned-out / legacy-wrapped, with reasons and flagged edge
  cases. This is the part that gives you confidence.

## Scope boundary (v1)

**Input is files. Output is files.** DDM Migrator reads `.mobileconfig`, transforms
payloads, and writes `*.ddm.json` declarations plus a report.

It does **not**:

- push to any MDM,
- call the Jamf / Intune / any MDM API,
- verify that declarations actually land on devices.

That boundary is deliberate — it's what makes v1 useful and shippable today. You
take the generated declarations into your own MDM workflow.

## Requirements

- macOS 14 or later
- Xcode 15+ / Swift 5.9+ (to build)

## Build & run

```sh
git clone https://github.com/mactesting12/ddm-migrator.git
cd ddm-migrator

# Run the app
swift run DDMMigratorApp

# Or build a release binary
swift build -c release
.build/release/DDMMigratorApp
```

Run the engine's unit tests (headless, no UI):

```sh
swift test
```

## Architecture

The logic and the UI are cleanly separated so the engine can be reused or wrapped
in a CLI later:

| Target | What it is |
|---|---|
| **`DDMCore`** | The engine. Pure Swift, no UI. CMS decode → payload walk → fan-out / MCX / legacy-wrap → declarations + report. Fully unit-tested. |
| **`DDMMigratorApp`** | The SwiftUI app: drop zone, results table, JSON preview, export. |

The two interesting tables to read first:

- `Sources/DDMCore/MappingTable.swift` — payload type → handler.
- `Sources/DDMCore/FanOutTable.swift` — the `applicationaccess` key → DDM domain
  routing. This is the single auditable place to adjust as Apple finalizes the
  declarative schemas.

## Provenance / clean-room note

Built clean-room from public Apple Developer documentation. Contains **no
employer-internal code, profile values, tenant identifiers, tokens, or
configuration**. All test fixtures are synthetic.

The DDM configuration domain strings are taken from Apple's public DDM / Platform
Deployment documentation for the macOS 27 cycle. The declarative **key names** in
the fan-out table are a best-effort mapping and the single place to adjust as the
schemas firm up; value **semantics** are passed through unchanged, and anything
that may need re-interpretation is flagged in the report rather than guessed.

## Contributing

Contributions welcome! See [CONTRIBUTING.md](CONTRIBUTING.md). The one hard rule:
**never commit real or non-synthetic profile data.**

## License

[MIT](LICENSE) © 2026 Machinery Software LLC
