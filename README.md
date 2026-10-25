# NotiForward

[中文](README_zh.md)

NotiForward (知会) is a macOS menu bar app that forwards selected Mac notifications to your iPhone through [Bark](https://github.com/Finb/Bark). There is no companion iOS app and no relay server of our own: install Bark on the iPhone, paste its device token into NotiForward, and you're done.

## Setup

1. Install Bark on the iPhone.
2. Launch NotiForward. Settings opens automatically until Bark is set up.
3. Paste one of these into the first field:
   - the **device token** from Bark. NotiForward registers it with the server and keeps the key it gets back.
   - the **key** from Bark's server list.
   - a full URL such as `https://api.day.app/yourkey/`. The server and key are split out automatically.
4. Click **Open Full Disk Access Settings** and switch NotiForward on. Forwarding starts within a few seconds; no relaunch is needed.
5. Use **Send Test Notification** to confirm delivery.

A self-hosted [bark-server](https://github.com/Finb/bark-server) can be set under **Advanced › Server**.

## How it works

1. The app polls the Notification Center database once per second. Full Disk Access is required because macOS has no public API for reading other apps' notifications.
2. App and keyword rules run locally. Rejected notifications never leave the Mac.
3. Accepted notifications are queued in SQLite and sent to `POST {server}/push`. The title is `App · Title`, and notifications are grouped by app unless that option is off.
4. Failed sends stay queued and retry with exponential backoff, up to one minute apart. Notifications older than six hours are dropped rather than delivered late. Notifications that arrive while forwarding is paused are skipped.

Full Disk Access has no request API, and the notification database is guarded separately, so failing to read it doesn't list the app in System Settings. The app therefore calls the private `TCCAccessRequest` once, which lists it with the switch off ([FullDiskAccess.swift](NotiForward/Capture/FullDiskAccess.swift)).

## Project layout

```
NotiForward/
  App/            entry point, menu bar, app model
  Capture/        notification database reader, app catalog, Full Disk Access
  Forwarding/     Bark client, rule engine, delivery queue
  Storage/        SQLite settings and queue
  Models/         settings and notification models
  Localization/   runtime language switching (L())
  Views/          menu and settings UI
  Resources/      assets, Localizable.xcstrings, InfoPlist.xcstrings
Tests/            unit tests (Swift Testing)
scripts/          localization.py
Design/           icon source
project.yml       XcodeGen spec (source of truth for NotiForward.xcodeproj)
```

## Development

```sh
./test.sh               # localization check + unit tests + Release build, install to /Applications, launch
./test.sh --no-install  # checks and tests only
./release.sh 1.1.0      # bump version, test, archive, Developer ID export, notarize, DMG, tag, GitHub release
./release.sh 1.1.0 --no-publish   # build the DMG only
```

Every notification's rule decision and every delivery is logged. In zsh, `log` is a shell builtin, so call `/usr/bin/log`:

```sh
/usr/bin/log stream --info --predicate 'subsystem == "com.ct106.notiforward"'
/usr/bin/log show --last 10m --info --predicate 'subsystem == "com.ct106.notiforward"'
```

`release.sh` notarizes when `APPLE_ID` and `APPLE_PASSWORD` (an app-specific password) are set. The project is generated from `project.yml` with [XcodeGen](https://github.com/yonaskolb/XcodeGen); both scripts regenerate it.

### Localization

The UI is available in English, 简体中文, 繁體中文, 日本語, 한국어, Deutsch, Français, Español, Italiano and Português (Brasil), and the language can be switched in Settings without relaunching. Every user-visible string goes through `L("…")`. `scripts/localization.py check` (run by `test.sh`) fails when a string is missing in any language, has mismatched placeholders, or is no longer used.

## Privacy

- Rules run on the Mac; only notifications that pass them are sent.
- Forwarded text goes to the configured Bark server and through Apple's push service to the iPhone. Use a self-hosted server if you don't want it to pass through `api.day.app`.
- Settings, the Bark key and the outgoing queue live in `~/Library/Application Support/NotiForward/noti-forward.sqlite`.
