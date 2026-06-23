# Contributing to DDM Migrator

Thanks for your interest! This is a small, focused tool and contributions are
welcome — bug fixes, new payload mappings, better fan-out routing, and edge-case
handling especially.

## The one hard rule

🚫 **Never commit real or non-synthetic profile data.**

No real `.mobileconfig` exports, no tenant identifiers, no organization names, no
tokens, no certificates, no internal payload values — ever. This is a public repo
and its history is permanent. Every fixture must be synthetic and invented.

## Build & test

```sh
swift build          # build everything (engine + app)
swift run DDMMigratorApp   # run the app
swift test           # run the headless engine tests
```

CI runs `swift build` and `swift test` on macOS for every PR.

## Project layout

- `Sources/DDMCore/` — the engine (pure logic, no UI). Start with
  `Migrator.swift` (the pipeline), `MappingTable.swift` (payload type → handler),
  and `FanOutTable.swift` (the `applicationaccess` key → DDM domain routing).
- `Sources/DDMMigratorApp/` — the SwiftUI app.
- `Tests/DDMCoreTests/` — unit + integration tests.
- `fixtures/` — synthetic `.mobileconfig` inputs.

Keep engine logic in `DDMCore` and UI in `DDMMigratorApp`. The engine must stay
unit-testable without any UI.

## Adding a payload mapping

1. Decide the handler in `Sources/DDMCore/MappingTable.swift`:
   - `.direct(domain:keys:)` for a clean 1:1 mapping,
   - `.fanOut` / `.mcx` for the special cases,
   - `.knownLegacy(reason:)` for payloads with no declarative equivalent.
2. For `applicationaccess` keys, add a row to `FanOutTable.routes`.
3. Add a test (see below).

## Adding a test fixture

1. Create a **synthetic** `.mobileconfig` under `fixtures/` (see
   `fixtures/README.md`). Invent every value.
2. Either load it via the `loadFixture(named:)` hook in
   `Tests/DDMCoreTests/DDMCoreTests.swift`, or build the profile in-code like the
   existing tests do.
3. Assert the classification, target domains, and that nothing is dropped.

## Commit style

We use [Conventional Commits](https://www.conventionalcommits.org/): `feat:`,
`fix:`, `docs:`, `test:`, `chore:`, `refactor:`.

## Code of conduct

Be kind and constructive. That's it.
