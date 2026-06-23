# Synthetic test fixtures

Every file in this directory is a **synthetic** `.mobileconfig` — invented by hand
to exercise a code path in the engine. None of it is real configuration data.

🚫 **Never add a real or non-synthetic profile here.** No real exports, tenant IDs,
organization names, SSIDs, certificates, tokens, or internal values. This is a
public repository and its history is permanent.

## What's here

| File | Exercises | Resulting status |
|---|---|---|
| `applicationaccess-mixed.mobileconfig` | The `com.apple.applicationaccess` fan-out (stage 2d): Intelligence + Siri + keyboard keys plus plain restriction keys that fall through to a legacy residual. | ⚠️ partial |
| `all-fanout-domains.mobileconfig` | Fan-out covering **all four** DDM domains (intelligence, external-intelligence, siri, keyboard) with no residual — a clean migration. | ✅ migrated |
| `mcx-managed-prefs.mobileconfig` | MCX unwrapping (stage 2c): two preference domains under `Forced[0].mcx_preference_settings`. | 📦 legacy wrap |
| `mcx-set-once.mobileconfig` | MCX using `Set-Once` instead of `Forced` — not auto-migrated, so it's flagged for review. | ⚠️ partial |
| `legacy-only.mobileconfig` | The legacy-wrap path (stage 2e): payloads with no declarative equivalent. | 📦 legacy wrap |
| `not-a-profile.mobileconfig` | A non-plist file — exercises per-file error handling (never a crash). | ⛔️ error |

## Adding a fixture

1. Write a synthetic profile. The easiest base is a plain XML plist with a
   `PayloadContent` array — see the existing files.
2. Keep it minimal and focused on one behavior.
3. Reference it from a test (see `Tests/DDMCoreTests/`), via the
   `loadFixture(named:)` hook or by asserting an end-to-end export.

## Generating a CMS-signed fixture (optional, local only)

To exercise the native CMS/PKCS7 decode path against a genuinely signed profile,
sign one of these with a throwaway self-signed cert — **do not commit the result
or the key**:

```sh
openssl req -x509 -newkey rsa:2048 -keyout key.pem -out cert.pem -days 1 -nodes \
  -subj "/CN=DDM Migrator Synthetic Signer"
openssl smime -sign -nodetach -binary \
  -in fixtures/applicationaccess-mixed.mobileconfig \
  -signer cert.pem -inkey key.pem -outform der -out /tmp/signed.mobileconfig

DDM_SIGNED_FIXTURE=/tmp/signed.mobileconfig swift test --filter testCMSSignedProfileIsDecodedNatively
```
