# VAULT

A personal credentials vault for Mac and iPhone. Offline. One owner. Every card is
encrypted on the device before it is written anywhere.

## What protects the data

| Layer | Detail |
|---|---|
| Vault key | Random 256-bit AES-GCM key. Encrypts the whole card set. |
| Master key | Wraps the vault key. Derived from the **master password** (PBKDF2-HMAC-SHA256, 1,000,000 rounds) combined with the **secret key** (160 random bits) through HKDF. Either alone is useless. |
| Secret key | Shown once on a key card. Stored on each enrolled device in the data-protection keychain behind Face ID / Touch ID (`biometryCurrentSet`), never inside the vault file. |
| One-time code | TOTP (RFC 6238) seed kept inside the encrypted payload, so one authenticator entry works on every device. Gate after decryption, with replay protection. |
| File | `VAULT1` magic + plaintext header (vault id, KDF salt, wrapped key) + AES-GCM body. Header is authenticated as additional data. Nothing in the header identifies the owner. |

Unlock on an enrolled device = Face ID / Touch ID releases the secret key, you type the
password, you type the current authenticator code. A new device needs the file, the
password and the key card.

All cryptography is Apple CryptoKit and CommonCrypto. No custom primitives.

## Sync

No server. **Sync, Export** writes an encrypted `.vault` file; AirDrop it to the other
device; **Sync, Import** merges it. Newer edit per card wins; deletions carry over as
tombstones kept for 90 days.

## Layout

```
Sources/VaultCore     crypto, model, file format, keychain, merge
Sources/VaultUI       SPEC-OPS design tokens, components, screens, app model
Sources/VaultCheck    self-test runnable with plain command line tools
Sources/VaultPreview  renders every screen to PNG for design review
Apps/                 thin macOS and iOS app targets (project.yml, XcodeGen)
Tests/                Swift Testing suites (run from Xcode)
```

## Build

```
brew install xcodegen
xcodegen generate          # writes Vault.xcodeproj
open Vault.xcodeproj       # pick your personal team under Signing for both targets
```

Command line only (no Xcode): `swift build`, `swift run VaultCheck`,
`swift run VaultPreview /tmp/previews`.

With a free Apple ID the iPhone build is valid for 7 days; reinstalling from Xcode
keeps the vault and keychain entries.

## Known limits

- No browser autofill. Possible later through a Credential Provider extension.
- Forgetting the master password or losing the key card on every device is unrecoverable by design.
- Screen recording and shoulder surfing are not solved by any vault. The Mac window
  is excluded from screen capture; iOS shows a cover in the app switcher.
- Attachments (photos of documents) are modelled but not yet exposed in the UI.

Fonts: Geist and Geist Mono, SIL Open Font License, see `Sources/VaultUI/Resources/Fonts/OFL-Geist.txt`.
