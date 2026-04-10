# Code Signing & Notarization

This guide covers how to sign and notarize VocaMac with an Apple Developer certificate for distribution outside the Mac App Store.

## Prerequisites

1. **Apple Developer Program membership** — $99/year from [developer.apple.com/programs](https://developer.apple.com/programs/)
2. **Developer ID Application certificate** — create one in [Certificates, Identifiers & Profiles](https://developer.apple.com/account/resources/certificates/add) and install it in your login Keychain
3. **App-specific password** — generate at [appleid.apple.com](https://appleid.apple.com) under Sign-In and Security → App-Specific Passwords

## One-Time Local Setup

### 1. Create the Certificate

1. Go to [developer.apple.com/account](https://developer.apple.com/account) → Certificates, IDs & Profiles → **Certificates** → `+`
2. Select **Developer ID Application**
3. Generate a CSR on your Mac:
   - Open **Keychain Access** → menu bar → **Certificate Assistant → Request a Certificate From a Certificate Authority...**
   - Enter your email, leave CA Email blank, select **Saved to disk**
4. Upload the `.certSigningRequest` file and download the resulting `.cer`
5. Import it to your login keychain:
   ```bash
   security import ~/Downloads/developerID_application.cer -k ~/Library/Keychains/login.keychain-db
   ```
6. If the cert shows as **not trusted**, install the intermediate CA:
   ```bash
   curl -O https://www.apple.com/certificateauthority/DeveloperIDG2CA.cer
   security import DeveloperIDG2CA.cer -k ~/Library/Keychains/login.keychain-db
   ```

### 2. Verify the Identity

```bash
security find-identity -v -p codesigning
# Expected: "Developer ID Application: YOUR NAME (TEAM_ID)"
```

### 3. Store Notarization Credentials

Generate an app-specific password at [appleid.apple.com](https://appleid.apple.com), then:

```bash
xcrun notarytool store-credentials "AC_PASSWORD" \
    --apple-id "your@email.com" \
    --team-id "YOUR_TEAM_ID"
```

Enter the app-specific password when prompted. This is stored securely in your login Keychain — you never need to pass it on the command line again.

## Building a Signed + Notarized DMG Locally

```bash
# Full build: Developer ID signed, notarized, stapled
make dmg

# Or directly:
./scripts/dist.sh

# Skip notarization (for local testing only)
./scripts/dist.sh --skip-notarize

# Skip signing entirely (ad-hoc, Gatekeeper will block)
./scripts/dist.sh --skip-sign
```

Output is placed in `dist/VocaMac-X.Y.Z-arm64.dmg`.

`build.sh` auto-detects the Developer ID certificate in your Keychain. To override:

```bash
CODE_SIGN_IDENTITY="Developer ID Application: JATIN KUMAR MALIK (92962VK378)" ./scripts/dist.sh
```

## GitHub Actions CI Setup

The release workflow (`release.yml`) handles signing and notarization automatically on every version tag push. You need to configure the following **repository secrets** once:

| Secret | Description |
|--------|-------------|
| `DEVELOPER_ID_CERT_P12` | Base64-encoded `.p12` export of your Developer ID certificate + private key |
| `DEVELOPER_ID_CERT_PASSWORD` | Password you set when exporting the `.p12` |
| `NOTARIZE_APPLE_ID` | Your Apple ID email |
| `NOTARIZE_TEAM_ID` | Your Apple Developer Team ID (e.g. `92962VK378`) |
| `NOTARIZE_PASSWORD` | The app-specific password for notarization |

### Exporting the .p12

1. Open **Keychain Access** → **My Certificates**
2. Right-click **Developer ID Application: YOUR NAME** → **Export**
3. Choose **Personal Information Exchange (.p12)**, set a strong password
4. Base64-encode it for the secret:
   ```bash
   base64 -i ~/Desktop/developerID.p12 | pbcopy
   ```
   Paste the output as the `DEVELOPER_ID_CERT_P12` secret.

### Adding Secrets to GitHub

Go to your repo → **Settings** → **Secrets and variables** → **Actions** → **New repository secret** for each of the five secrets above.

## Manual Signing Steps (Reference)

### Sign the app

```bash
# Sign nested bundles first
find VocaMac.app/Contents/Resources -name "*.bundle" -exec \
    codesign --force --sign "Developer ID Application: JATIN KUMAR MALIK (92962VK378)" {} \;

# Sign the main app
codesign --force --sign "Developer ID Application: JATIN KUMAR MALIK (92962VK378)" \
    --identifier com.vocamac.app \
    --entitlements VocaMac.entitlements \
    VocaMac.app
```

### Create and sign the DMG

```bash
# Create DMG
hdiutil create -volname VocaMac -srcfolder VocaMac.app -ov -format UDZO VocaMac.dmg

# Sign DMG
codesign --sign "Developer ID Application: JATIN KUMAR MALIK (92962VK378)" VocaMac.dmg
```

### Notarize and staple

```bash
xcrun notarytool submit VocaMac.dmg \
    --keychain-profile "AC_PASSWORD" \
    --wait

xcrun stapler staple VocaMac.dmg
```

### Verify

```bash
# Gatekeeper check
spctl --assess --type open --context context:primary-signature VocaMac.dmg

# Signature depth check
codesign --verify --deep --strict VocaMac.app

# Notarization history
xcrun notarytool history --keychain-profile "AC_PASSWORD"
```

## Troubleshooting

| Problem | Fix |
|---------|-----|
| `0 valid identities found` | Import the intermediate CA: `DeveloperIDG2CA.cer` from Apple |
| `certificate is not trusted` | Same as above — missing intermediate CA |
| Notarization fails | Run `xcrun notarytool log <submission-id> --keychain-profile "AC_PASSWORD"` for details |
| `invalid signature` | Make sure all nested `.bundle` files are signed before the main app |
| Permissions reset on rebuild | Expected with ad-hoc signing; Developer ID signing prevents this across machines but not local rebuilds |
