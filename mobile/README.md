# AgroBenta Mobile

Flutter client for the AgroBenta Laravel API. Buyer, seller and seller
verification functionality for the AgroBenta livestock marketplace.

**There is no admin mobile application.** Administrative functions live in the
React Admin Web at `../frontend/`.

## Status — M0 (foundation)

The foundation is in place and validated. **No feature screens exist yet.** The
app currently shows a single placeholder screen that demonstrates the theme,
the resolved API configuration and the token/API client stack.

Deliberately not built yet: login, registration, home, marketplace, seller
verification, listing management, AI price suggestion, transactions,
notifications, messaging, profile.

### Blocked

**M1 authentication cannot start.** The backend exposes no mobile-facing API —
see the *API Gap register* in [AGENTS.md](AGENTS.md). In short, there is no
non-admin login, and `AuthService::login()` refuses to issue a token to anyone
who is not an administrator. That needs backend work and explicit approval
first.

## Documentation

| File | Purpose |
|---|---|
| [AGENTS.md](AGENTS.md) | Development rules: architecture, API contract, authentication, the single-account model, backend safety, local development, the API gap register |
| [DESIGN.md](DESIGN.md) | Visual source of truth for this app |

Project-wide rules live in the repository root: `../AGENTS.md`, `../DESIGN.md`,
`../backend/AGENTS.md`, `../frontend/AGENTS.md`. Read those first.

## Prerequisites

* Flutter 3.44.4 (stable) — `flutter doctor`
* Android SDK for Android builds
* The backend running in Docker, serving Laravel on `http://localhost:8001`
  (see the root `../README.md`)

## Running

```sh
flutter pub get

# Physical device (default) — resolves to http://<your-lan-ip>:8001/api
flutter run --dart-define=API_BASE_URL=http://<your-lan-ip>:8001/api

# Android emulator — opt into the host alias explicitly
flutter run --dart-define=ANDROID_RUN_TARGET=emulator

# iOS simulator
flutter run -d <ios-device-id>
```

The base URL is resolved by `lib/core/config/app_config.dart`. A native Android
build defaults to the **physical-device** address — `http://<your-lan-ip>:8001/api`,
this machine's LAN IP. The emulator's `10.0.2.2` alias is chosen **only** with
`--dart-define=ANDROID_RUN_TARGET=emulator`, so a physical build can never
silently fall back to it. Override the URL per build rather than editing
source:

```sh
# Point anywhere explicitly (staging, another machine, etc.)
flutter run --dart-define=API_BASE_URL=https://api.staging.example.test/api

# Production (HTTPS placeholder)
flutter build apk --release --dart-define=API_BASE_URL=https://CHANGE_THIS_PRODUCTION_API_BASE_URL/api
# or
flutter build ios --release --dart-define=API_BASE_URL=https://CHANGE_THIS_PRODUCTION_API_BASE_URL/api
```

> **Android emulator → host is `10.0.2.2`, not `localhost`.** The emulator runs
> behind a virtual network bridge, so `localhost` refers to the emulator
> itself. See AGENTS.md §G.

### Google sign-in (Android only)

The "Continue with Google" button appears only on Android, and only when the
build is given the backend's Google OAuth **Web application** client ID — the
same value as `GOOGLE_CLIENT_ID` in `backend/.env`:

```sh
flutter run --dart-define=ANDROID_RUN_TARGET=emulator \
            --dart-define=GOOGLE_SERVER_CLIENT_ID=CHANGE_THIS_GOOGLE_WEB_CLIENT_ID.apps.googleusercontent.com
```

Google Cloud Console also needs an **Android** OAuth client for package
`com.agrobenta.agrobenta_mobile` with the SHA-1 of the key that signs the build
(`cd android && ./gradlew signingReport`). Each developer's debug keystore has
its own SHA-1, so each one must be added; a release build needs the release
key's SHA-1. No client secret is used by the app or the backend.

### Push notifications (Android only)

Firebase Cloud Messaging is configured by `android/app/google-services.json`
(Firebase project `agrobenta-proj`, package `com.agrobenta.agrobenta_mobile`).
It is committed: it identifies the Firebase project but holds no secret. To
point the app at another Firebase project, replace that file with the one from
Firebase Console → **Project settings → Your apps**.

After sign-in the app asks for notification permission (Android 13+) and sends
the phone's FCM token to `POST /api/devices`. Pushes arrive only when the
backend has `FCM_CREDENTIALS` set and its queue worker is running (root
`README.md`). A push received while the app is open is not shown, because the
open app already updates live; tapping a push opens the Notifications screen.
iOS push needs an APNs key and is not set up.

The Android app icon is `assets/images/AgroBentaLogo.png`
(`res/mipmap-*/ic_launcher.png`, plus an adaptive icon on a white background in
`res/mipmap-anydpi-v26/`). The push status-bar icon,
`res/drawable-*/ic_stat_agrobenta.png`, is a white silhouette of the logo's
ring, leaves and cart: Android draws that icon in one colour, so the full-colour
logo would show as a white square. It is tinted brand green (`#006B4F`) through
the Firebase `default_notification_*` entries in `AndroidManifest.xml`. If the
logo changes, regenerate all of these.

Cleartext HTTP is denied by default on Android. Debug builds allow it broadly
(`android/app/src/debug/res/xml/network_security_config.xml`) so a phone on the
LAN can reach the plain-HTTP Docker stack; `src/main` stays strict and permits
it only for `10.0.2.2`, `localhost` and `127.0.0.1`. Production must be HTTPS.

## Validation

Run all four before reporting work as complete:

```sh
flutter pub get
flutter analyze          # must be clean
flutter test --dart-define=ANDROID_RUN_TARGET=emulator   # must pass
flutter build apk --debug
```

`flutter test` runs as Android, and a native Android build has no default API
URL (see "Running" above), so any test that makes an API call needs one of
the two defines. `ANDROID_RUN_TARGET=emulator` is the one the suite is written
for; plain `flutter test` fails with "Physical Android build requires
--dart-define=API_BASE_URL".

## Layout

```text
lib/
├── core/
│   ├── config/          AppConfig — build-time config, base URL
│   ├── constants/       transport constants
│   ├── network/         ApiClient, ApiException
│   ├── storage/         TokenStore (interface) + TokenStorage (keystore)
│   ├── theme/           AppColors, AppSpacing, AppTheme
│   └── utils/           json_utils
├── models/              mirrors of Laravel API Resources
├── main.dart            composition root
└── (features/, services/, repositories/, widgets/ come with their phase)
```

Feature folders are created when a feature is built, not in advance.
