# VAULT

A personal vault for credentials and private files, for Mac and iPhone. Offline. One owner.
Everything is encrypted on the device before it is written anywhere. There is no server,
no account, and nothing leaves your machine unless you export it.

Each person builds their own copy with their own free Apple ID. Your copy is yours alone:
own password, own secret key, own data. The repo holds only code.

## Set up on a Mac

You need a Mac running macOS 14 or newer, about 20 minutes, and roughly 15 GB free for Xcode.

1. **Install Xcode** from the App Store (free). Open it once and let it finish installing components.
2. **Sign in with your Apple ID** in Xcode: menu Xcode, Settings, Accounts, press +, Apple ID.
   This creates your free "Personal Team". No paid developer account is needed.
3. **Get the code.** In Terminal:

   ```
   git clone https://github.com/suwe-code/vault.git
   cd vault
   ./setup.sh
   ```

   The script finds your team, asks for a short name to make the app id yours
   (for example `alex`, which becomes `com.alex.vault`), installs XcodeGen if needed, builds,
   puts `VAULT.app` in Applications and opens it. The first build takes a few minutes.

4. **First launch.** Choose Create vault, pick a master password of at least 12 characters,
   and print or save the key card the app shows. Then enrol Touch ID. From then on,
   unlock is Touch ID plus your password.

The key card is shown once. Keep it on paper, away from your Mac. Without it, a new device
can never open your vault, even with the password. That is the design, not a bug.

### Every 7 days

A free Apple ID only signs builds for 7 days. After that the app refuses to open.
Run `./setup.sh` again. It rebuilds and reinstalls in about a minute, and your vault,
files and Touch ID enrolment are untouched. The script prints the next expiry date.

If a week ever goes by and the app will not open, nothing is lost. Run the script.

### iPhone

Connect the phone with a cable, open `Vault.xcodeproj` in Xcode, pick the `VAULT-iOS` scheme
and your phone as the destination, press Run. On the phone, allow the developer app under
Settings, General, VPN & Device Management. The 7-day rule applies there too.

Move your vault to the phone with Sync, Export on the Mac, AirDrop the `.vault` file,
open it on the phone, and type your password and the key card once.

## Using it

- **CARDS** holds logins, bank details, cards, identity documents, people (family and
  contacts with their phone, address and document numbers) and notes. Click a row to
  copy it. Secrets clear from the clipboard after 30 seconds.
- **FILES** holds photos, scans, PDFs and any other file. Drop files in or use Add files.
  Each one is encrypted on disk. Open, share, or download a copy while the vault is open.
  Share and download can wrap the file in a password for the recipient: PDFs and images
  become an encrypted PDF, other files a protected ZIP. Every plain copy is deleted when the
  vault locks or the app quits. Files stay on the device they were added to; they are not
  part of the `.vault` export.
- **SYNC** exports and imports the encrypted `.vault` file between your own devices.
  Newer edit per card wins, deletions carry over.
- **SETTINGS** sets the timer. When it runs out the Mac app quits. Change the password,
  show the key card again, choose the download folder, or wipe this device.

## What protects the data

| Layer | Detail |
|---|---|
| Vault key | Random 256-bit AES-GCM key. Encrypts the whole card set. |
| Master key | Wraps the vault key. Derived from the **master password** (PBKDF2-HMAC-SHA256, 1,000,000 rounds) combined with the **secret key** (160 random bits) through HKDF. Either alone is useless. |
| Secret key | Shown once on the key card. Stored on each enrolled device in the data-protection keychain behind Touch ID or Face ID, never inside the vault file. |
| Files | Each file is AES-GCM encrypted under a key derived from the vault key. Names and thumbnails live in an encrypted index. On disk there are only opaque blobs. |
| File format | `VAULT1` magic, plaintext header (vault id, KDF salt, wrapped key), AES-GCM body. The header is authenticated. Nothing in it identifies the owner. |

A stolen vault file cannot be brute-forced: the attacker also needs the 160-bit secret key.
All cryptography is Apple CryptoKit and CommonCrypto. No custom primitives.

Where the data lives on a Mac:

```
~/Library/Containers/<your app id>/Data/Library/Application Support/VAULT/
    vault.vault             your cards, encrypted
    vault.previous.vault    the version before the last save
    media/                  encrypted files and their index
```

## Known limits

- No browser autofill.
- Forgetting the master password, or losing the key card on every device, is unrecoverable by design.
- A protected ZIP uses the classic zip encryption, which is weak. For anything sensitive,
  share PDFs and images, which become properly encrypted PDFs.
- While a file is open in another app, a plain copy exists in a private folder until the vault locks.
- Screen recording and shoulder surfing are not solved by any vault. The Mac window is excluded
  from screen capture; iOS shows a cover in the app switcher.

## Troubleshooting

**"Build failed" mentioning signing or a team.** Xcode is not signed in, or the account has no
Personal Team yet. Open Xcode, Settings, Accounts, check the Apple ID is there, then run
`./setup.sh --reset`.

**The app says "No vault on this device" but you had one.** Do not press Create vault.
Check that `Config/Local.xcconfig` still has the same name you first chose. The data folder is
tied to that app id. Fix the file, run `./setup.sh`, and the vault is back.

**"VAULT would like to access files in your Desktop folder."** That is the first download.
Allow it, or choose another folder in Settings.

**Telegram or WhatsApp missing from Share.** Telegram appears once its share extension is on:
System Settings, General, Login Items & Extensions, Sharing. WhatsApp for Mac has no share
extension, so the app offers a WhatsApp entry that copies the file and opens WhatsApp;
paste it into the chat.

## For developers

```
Sources/VaultCore     crypto, model, file format, keychain, media store, merge
Sources/VaultUI       SPEC-OPS design tokens, components, screens, app model
Sources/VaultCheck    crypto self-test, plain command line
Sources/VaultPreview  renders every screen to PNG for design review
Apps/                 thin macOS and iOS targets, generated by XcodeGen from project.yml
Config/               Local.xcconfig holds your team and app id prefix (not committed)
Tests/                Swift Testing suites (run from Xcode)
```

Command line only: `swift build`, `swift run VaultCheck`, `swift run VaultPreview /tmp/previews`.

Fonts: Geist and Geist Mono, SIL Open Font License, see `Sources/VaultUI/Resources/Fonts/OFL-Geist.txt`.
