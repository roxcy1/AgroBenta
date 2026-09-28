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

# Android emulator — 10.0.2.2 is the default on Android, no flag needed
flutter run

# iOS simulator
flutter run -d <ios-device-id>
```

The base URL is resolved by `lib/core/config/app_config.dart`. Override it per
build rather than editing source:

```sh
# Physical device on the same Wi-Fi network
flutter run --dart-define=API_BASE_URL=http://192.168.1.20:8001/api

# Staging
flutter run --dart-define=API_BASE_URL=https://api.staging.example.test/api
```

> **Android emulator → host is `10.0.2.2`, not `localhost`.** The emulator runs
> behind a virtual network bridge, so `localhost` refers to the emulator
> itself. See AGENTS.md §G.

Cleartext HTTP is denied by default on Android and permitted only for
`10.0.2.2`, `localhost` and `127.0.0.1` — see
`android/app/src/main/res/xml/network_security_config.xml`. Production must be
HTTPS.

## Validation

Run all four before reporting work as complete:

```sh
flutter pub get
flutter analyze          # must be clean
flutter test             # must pass
flutter build apk --debug
```

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
