# Homepage

A tiny native iOS **WKWebView** shell for the Blinky Homepage dashboard, installed as **Homepage**. Built for the iPhone Duo.

The Xcode project/repo is still named `BlinkyShell`; the installed app name and icon label are **Homepage**.

It exists because an installed PWA cannot keep cross-origin links inside its own webview — iOS opens them in the in-app browser (`SFSafariViewController`). A native shell owns the webview, so Homepage and every linked app stay in one place, and a single injected script can apply the Duo viewport fix to all of them.

## What it does

- Loads `http://blinky-ubuntu:3005/` by default (change it in the in-app Settings sheet).
- Keeps every `http`/`https` navigation in one `WKWebView`.
- Normal `target=_blank` links stay in the same webview; OAuth popups (Plex, Google, Authentik) open in a real child webview so `window.opener`, `postMessage`, and `window.close()` work.
- Text selection and copy/paste are enabled even if a page tries to disable them.
- Home, Back, Forward, Reload, and Settings buttons in a floating toolbar.
- The toolbar fades into a small button in the **bottom-left corner** after 5 seconds of inactivity; tap it to bring the controls back to the center.
- Dark iOS-style app icon generated from `Design/AppIcon.svg`.
- Full-screen on iPhone Duo: status bar and home indicator hidden, webview edge-to-edge, `obscuredContentInsets = .zero`.
- Injects a bounded Duo viewport fix into every main-frame page. It only fires when the reserved strip is **60–160 px**, so it does not widen a normal notch (44–59 px) or a Split View window (hundreds of px).
- Persistent cookies, file upload, downloads, JS dialogs, basic auth, and dark mode.

## Project layout

```
project.yml                     XcodeGen project definition
Design/AppIcon.svg              Source SVG for the app icon
BlinkyShell/
  BlinkyShellApp.swift          App entry point
  ContentView.swift             WebView + floating toolbar + Settings sheet
  WebView.swift                 WKWebView, navigation/download/upload delegates
  WebViewModel.swift            Observable navigation state
  Settings.swift                Persisted start URL
  Config.swift                  Default start URL
  DuoFit.swift                  Injected viewport fix
  Assets.xcassets/              App icon
.github/workflows/build.yml     GitHub Actions IPA build
ExportOptions.plist.template    Reference for local signed exports
```

## Build with GitHub Actions

1. Push this folder to a GitHub repository.
2. Open **Actions → Build IPA → Run workflow**.
3. Download the `BlinkyShell-ipa` artifact when it finishes.

The workflow runs on the `xcode-27` runner image and selects **Xcode 27.2** when present (it is on the current image), falling back to the newest installed 27.x. That SDK is what gives the app the edge-to-edge iPhone Duo layout.

### Option A — unsigned IPA, sign locally (no secrets)

Do nothing. The workflow produces `BlinkyShell-unsigned.ipa`.

Sign and install it with one of:

- **Sideloadly** — drag the IPA in, sign with your certificate or Apple ID.
- **AltStore / SideStore** — My Apps → `+` → select the IPA.

With a paid team certificate the app lasts **1 year** instead of 7 days.

### Option B — sign in GitHub Actions

Add these **repository variables** (Settings → Secrets and variables → Actions → Variables):

| Variable | Value |
| --- | --- |
| `TEAM_ID` | Your 10-character Apple Team ID (required) |
| `BUNDLE_ID` | Optional. Defaults to `cool.swan.blinkyshell`. Must match the App ID/profile. |
| `EXPORT_METHOD` | `ad-hoc` (default) or `development` |
| `SIGNING_IDENTITY` | `Apple Distribution` (default) or `Apple Development` |

Add these **repository secrets**:

| Secret | Value |
| --- | --- |
| `BUILD_CERTIFICATE_BASE64` | Base64 of your `.p12` (certificate **and private key**) |
| `P12_PASSWORD` | Password for the `.p12` |
| `PROVISIONING_PROFILE_BASE64` | Base64 of the `.mobileprovision` |

When `BUILD_CERTIFICATE_BASE64` is set, the workflow imports the certificate into a temporary keychain, installs the profile, archives, exports a signed IPA, and uploads it.

Base64-encode on macOS:

```sh
base64 -i cert.p12 | pbcopy
base64 -i profile.mobileprovision | pbcopy
```

On Linux:

```sh
base64 -w0 cert.p12
base64 -w0 profile.mobileprovision
```

## Creating the certificate and profile on someone else's team

You are a member of a paid team but not the account holder, so you need either the right role or the account holder's help.

1. **Role.** You need **Admin** or **App Manager** to create certificates, App IDs, and profiles. If you only have Developer, ask the account holder.
2. **Private key.** A certificate without its private key cannot sign. If someone else created it, ask them for a `.p12` export (certificate + private key), or create a new certificate for your user.
3. **Register the Duo.** In the developer portal: **Devices → +**, add the Duo's UDID. Get it from Finder (click the device → serial number area) or with `idevice_id -l`.
4. **App ID.** Create an App ID matching `BUNDLE_ID` (or use a wildcard App ID).
5. **Profile.** Create an **Ad Hoc** (or **Development**) provisioning profile that includes the Duo.
6. **Export.**
   - Download the `.mobileprovision`.
   - Export the signing certificate as `.p12` from **Keychain Access → My Certificates → Export**.
7. **Upload.** Base64 both files and add them as the secrets above.

If you use a **development** profile, also set `SIGNING_IDENTITY=Apple Development` and `EXPORT_METHOD=development`.

> If you cannot create certificates/profiles yourself, the unsigned artifact (Option A) still works: sign it locally with a `.p12` + `.mobileprovision` that the account holder provides.

## Install and trust

1. Install the IPA with Sideloadly or AltStore/SideStore.
2. On the device: **Settings → General → VPN & Device Management → [your developer] → Trust**.
3. Launch **Homepage**.

A paid team certificate/profile is valid for one year. Re-sign before it expires.

## Configuration

- Tap the **gear** icon to change the start page. The Home button loads it.
- Default: `http://blinky-ubuntu:3005/`
- On Tailscale, `blinky-ubuntu` needs MagicDNS enabled. If it does not resolve, use the machine's `100.x` Tailscale address.
- **Homepage host allow-list:** if you use a different hostname or IP, add it to `HOMEPAGE_ALLOWED_HOSTS` in `/docker/homepage/docker-compose.yml` (for example `100.110.185.96:3005`) and restart Homepage. Otherwise Homepage returns a 400 “Host not allowed”.
- To change the default for new installs, edit `BlinkyShell/Config.swift`.

## iPhone Duo notes

- The workflow builds with the **iOS 27.2 SDK**, which is what enables the edge-to-edge layout on the Duo.
- The status bar and home indicator are hidden, and the webview is sized to the full window.
- The injected script widens the page's viewport meta to `screen.width` only when the reserved right strip looks like the Duo outer display (60–160 px). It restores the original meta when the condition no longer holds.
- If an app still leaves a right gap, the next step is to log the measured `reserved`/`inset` values and tune the bounds.

## Passkeys (`auth.swan.cool`)

`WKWebView` only allows passkeys for domains declared in the app's Associated Domains entitlement. The app now ships:

- `BlinkyShell/BlinkyShell.entitlements` with `webcredentials:auth.swan.cool`.

To complete the setup:

1. Enable **Associated Domains** on the App ID (`cool.swan.blinkyshell`) in the Apple Developer portal and regenerate the provisioning profile.
2. Set your 10-character Team ID in `/docker/authentik/.env` and restart Authentik:
   ```sh
   BLINKY_TEAM_ID=ABCDE12345
   ```
   The patched AASA view (`custom/apple_site_association.py`, bind-mounted into the container) merges `webcredentials: { "apps": ["<TEAM_ID>.cool.swan.blinkyshell"] }` into Authentik's existing `authsrv` block.
3. Sign the app with the updated profile. An unsigned IPA cannot carry the entitlement.
4. Delete and reinstall the app. Apple's CDN caches the AASA (up to 24 hours). For testing, a development-signed build with `webcredentials:auth.swan.cool?mode=developer` bypasses the CDN.

Google passkeys (`accounts.google.com`) cannot work in a `WKWebView` because Google's AASA cannot list your app. Use Safari/SFSafariViewController for that login, or use a password/2FA.

## Known limitations

- **Self-signed HTTPS** is rejected by `WKWebView` and cannot be overridden with public API. Use HTTP, install the CA profile on the device, or expose the app with `tailscale serve` (trusted `*.ts.net` certificate).
- **SSO popups**: OAuth popups for the hosts listed in `WebView.swift` (`plex.tv`, `accounts.google.com`, `auth.swan.cool`, etc.) open in a child webview. Add more hosts there if another provider needs a popup.
- **No push notifications** (requires native APNs).
- **Sideload expiry**: paid team = 1 year; free Apple ID = 7 days.

## Troubleshooting

| Symptom | Fix |
| --- | --- |
| "Untrusted Developer" | Trust the certificate in Settings → General → VPN & Device Management. |
| "Unable to install" | `BUNDLE_ID` must match the App ID in the provisioning profile. |
| "No signing certificate found" | The `.p12` is missing its private key, or `SIGNING_IDENTITY` is the wrong name. |
| Build picks the wrong Xcode | The runner image changed; the workflow falls back to the newest 27.x, then the newest overall. |
| Duo still has a right gap | The app is probably being clamped by WebKit. Open Safari Web Inspector (the webview is inspectable) and look for the `[Homepage] duo-fit` console line, then adjust `DuoFit.swift`. |
| Pages cannot reach the LAN | Allow **Local Network** for Homepage in Settings → Privacy & Security → Local Network. |
| Passkey prompt doesn't appear on auth.swan.cool | Sign with a profile that includes Associated Domains, set `BLINKY_TEAM_ID`, and confirm the AASA lists `<TEAM_ID>.cool.swan.blinkyshell`. |
