# NotiForward

[中文](README_zh.md) · [Website](https://notiforward.ct106.com) · [Privacy](https://notiforward.ct106.com/privacy.html)

NotiForward (知会) is a macOS menu bar app that forwards the Mac notifications you choose to one or more devices through [Bark](https://bark.day.app). There is no companion iOS app and no server of our own: install Bark on each receiving device, add its token or key to NotiForward, and pick the apps to forward.

## Install

- **Direct download**: the notarized DMG from [Releases](https://github.com/chentao1006/NotiForward/releases/latest), or Homebrew:
  ```sh
  brew install --cask chentao1006/tap/notiforward
  ```
- **Mac App Store**: the same app, with every feature included.

Requires macOS 12 or later.

## Setup

1. Install Bark on each iPhone or iPad that should receive notifications.
2. Launch NotiForward. Settings opens on the **Client** tab until Bark is set up.
3. In the key list, paste one of these:
   - the **device token** from Bark. NotiForward registers it with the server and keeps the key it gets back.
   - the **key** from Bark's server list.
   - a full URL such as `https://api.day.app/yourkey/`. The server and key are split out automatically.
4. Use the plus button below the list to add more keys. All devices share the server, interruption level, grouping, icon, and tap-action settings.
5. Under **General → Status**, click **Grant Access…** and confirm. The panel opens on the Notification Center folder; this is the only folder the app reads. Forwarding starts within a few seconds.
6. Pick the apps to forward under **Forwarding Rules**. If a notification comes from a helper or background process that is absent from the app list, add it from **Recent Sources** at the top of the picker. Then use **Send Test Notification** to confirm delivery to every device.

A self-hosted [bark-server](https://github.com/Finb/bark-server) can be set once for all devices under **Client → Advanced → Server**.

## How it works

1. **Capture.** The app watches the Notification Center database (`~/Library/Group Containers/group.com.apple.usernoted`) with kernel file events and reads new rows only when it changes, so it sleeps between notifications. A 60-second safety check covers missed events. Access comes from a security-scoped bookmark of that one folder, granted in a system open panel; no Full Disk Access is needed.
2. **Rules.** App and keyword rules run locally. Notifications that don't match never leave the Mac. Recently captured source identifiers are kept locally so processes missing from the app catalog can be added to the rules.
3. **Delivery.** Accepted notifications are queued in SQLite and sent concurrently to every configured Bark device. Each push carries:
   - title `App · Title`, grouped by app;
   - the app's icon, looked up on the App Store by bundle ID;
   - a tap URL built from the Mac app's URL scheme (for example `tg://` for Telegram), so tapping opens the same app on iPhone.
4. **Retries.** If delivery fails on one device, only that device remains queued and retries with exponential backoff, so devices that already succeeded do not receive duplicates. Retries are up to one minute apart. Notifications older than six hours are dropped rather than delivered late, and notifications that arrive while forwarding is paused are skipped.

Notification Center itself commits a new notification to its database a few seconds after showing it, so pushes arrive about 3–5 seconds after the Mac shows the notification.

## Project layout

```
NotiForward/
  App/            entry point, menu bar, app model
  Capture/        database reader, change monitor, folder access, app catalog
  Forwarding/     Bark client, rule engine, delivery queue, icon lookup
  Storage/        SQLite settings and queue
  Models/         settings, notification models
  Localization/   runtime language switching (L())
  Views/          menu and settings UI
  Resources/      assets, string catalogs, privacy manifest
  NotiForward.entitlements           direct build (sandbox + one migration exception)
  NotiForwardAppStore.entitlements   App Store build (no temporary exceptions)
Tests/            unit tests (Swift Testing)
scripts/          localization.py
index.html, index.css, privacy.html, CNAME   website (GitHub Pages)
project.yml       XcodeGen spec (source of truth for NotiForward.xcodeproj)
```

There are two app targets built from the same sources. `NotiForward` is the direct download, with Sparkle updates. `NotiForwardAppStore` is built with `-D APP_STORE`, which leaves out Sparkle and the code that needs a temporary-exception entitlement.

## Development

```sh
./test.sh               # localization check, unit tests, App Store build check, then Release build, install and launch
./test.sh --no-install  # checks and tests only
```

Logs: every rule decision, delivery and capture event goes to the unified log. In zsh, `log` is a shell builtin, so call `/usr/bin/log`:

```sh
/usr/bin/log stream --info --predicate 'subsystem == "com.ct106.notiforward"'
```

### Localization

The UI is available in English, 简体中文, 繁體中文, 日本語, 한국어, Deutsch, Français, Español, Italiano and Português (Brasil), and the language can be switched in Settings without relaunching. Every user-visible string goes through `L("…")`. `scripts/localization.py check` (run by `test.sh`) fails when a string is missing in any language, has mismatched placeholders, or is no longer used.

## Release

```sh
./release.sh 1.1.0                  # direct release: GitHub + Homebrew
./release.sh 1.1.0 --app-store      # also upload the App Store build to App Store Connect
./release.sh 1.1.0 --no-publish     # build and notarize the DMG only
```

The direct release bumps the version in `project.yml` and runs the tests. It then archives, exports with Developer ID, and notarizes the app. Next it builds the DMG, notarizes and staples it, and verifies it with `stapler` and Gatekeeper. Finally it commits, tags, creates the GitHub release, and updates the `chentao1006/tap` cask through `release-to-brew.sh`.

- Notarization needs `APPLE_ID` and `APPLE_PASSWORD` (an app-specific password). Failed uploads are retried, and a submission that isn't `Accepted` stops the release.
- An un-notarized DMG is never published; `ALLOW_UNNOTARIZED=1` overrides that.
- `SKIP_HOMEBREW_RELEASE=1` skips the cask update.
- `--app-store` uploads with the Apple ID signed in to Xcode. Submit the build for review in App Store Connect.

### App Store submission

Before the first submission, in App Store Connect:

- Set the privacy policy URL to `https://notiforward.ct106.com/privacy.html`.
- Fill in App Privacy: **Other User Content** for App Functionality and **Product Interaction** for Analytics; neither is linked to the user or used for tracking. This matches the app and Aptabase privacy manifests.

Suggested review notes:

> NotiForward forwards notifications the user chooses from their Mac to one or more of their own devices through Bark, a free open-source push app. To read notifications, the user selects the Notification Center data folder (~/Library/Group Containers/group.com.apple.usernoted) once in a standard open panel; the app keeps a read-only security-scoped bookmark to that folder and accesses nothing else. Filtering rules run on the Mac, and only matching notifications are sent, over HTTPS, to the Bark servers the user configures. To test: install Bark on an iPhone, add its device key in Settings → Client, grant folder access in Settings → General, choose an app in Forwarding Rules, and click Send Test Notification.

## Privacy

- There is no account, advertising, or cross-app tracking. Aptabase receives anonymous product-interaction events and standard technical context, but never notification content, Bark credentials, app bundle identifiers, or rule keywords.
- Rules run on the Mac; only notifications that pass them are sent.
- Forwarded text goes to each device's configured Bark server and through Apple's push service. Use a self-hosted server if you don't want it to pass through `api.day.app`.
- App icons are looked up by bundle ID on Apple's App Store lookup service; no notification content is sent there.
- Settings, every device's Bark key, recent notification source names and identifiers, and the outgoing queue live in the app's sandbox container. Recent sources never contain notification titles or bodies.

See the full [privacy policy](https://notiforward.ct106.com/privacy.html).
