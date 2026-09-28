# Mobile — AI Agent Instructions

## Scope

This file applies **only** to `mobile/`.

The mobile application is a Flutter/Dart client for the AgroBenta Laravel API.
It is the customer-facing application: buyers, sellers, and seller verification.

**There is no admin mobile application.** Administrative functions stay in the
React Admin Web at `frontend/`. Do not port them, and do not add admin routes,
admin screens, or admin API calls to this app.

Inspect existing code before making changes. Follow the architecture, naming and
UI patterns already established here.

---

## Source-of-truth order

When rules appear to conflict, resolve in this order:

1. Root `AGENTS.md`
2. Root `DESIGN.md` (visual identity and brand)
3. Approved AgroBenta functional/system documentation —
   `docs/AGROBENTA_FUNCTIONAL_DOCUMENTATION.md`
4. Backend API implementation and contracts (`backend/routes/api.php`,
   controllers, requests, resources, services, repositories, models,
   migrations) — the actual behaviour wins over any assumption
5. This file
6. `mobile/DESIGN.md` (mobile-specific visual rules only)
7. Existing Flutter code in `mobile/`

Consequences:

* **Business rules** come from `docs/AGROBENTA_FUNCTIONAL_DOCUMENTATION.md`.
  Where it is silent, **stop and report** — do not invent a rule. That document
  is **approved**: do not edit it to settle a disagreement.
* **API behaviour** must match the actual Laravel implementation, not a
  document describing it.
* **Mobile visual rules** govern only this app's UI. They never override the
  brand identity in the root `DESIGN.md`.
* Never change a higher-level rule to make implementation easier.

---

## A. Architecture

Flutter, feature-oriented. The layering is fixed and the dependency direction
is one-way:

```text
widgets / screens        (UI only — no business logic, no HTTP)
        ↓
state / controllers      (presentation logic for a feature)
        ↓
repositories             (orchestration; the mobile analogue of a Service)
        ↓
services                 (API calls, one per backend concern)
        ↓
ApiClient                (transport only)
```

```text
lib/
├── core/
│   ├── config/          AppConfig — build-time configuration, base URL
│   ├── constants/       transport constants (headers, timeouts, storage keys)
│   ├── network/         ApiClient, ApiException
│   ├── storage/         TokenStore (interface) + TokenStorage (keystore)
│   ├── theme/           AppColors, AppSpacing, AppTheme
│   └── utils/           json_utils and other pure helpers
│
├── models/              data classes mirroring Laravel API Resources
├── services/            thin API surface per backend concern
├── repositories/        feature orchestration over services
├── features/            one folder per feature (see below)
├── widgets/             shared, reusable widgets
└── main.dart            composition root
```

`features/` folders are created **when the feature is built**, not in advance.
An empty `features/auth/` directory is not a plan; it is noise.

### Rules

* Separate UI, state, services/repositories, models and API communication.
  Do not collapse these layers to save a file.
* **No business logic in widgets.** A `build` method assembles widgets. It does
  not parse JSON, format money, decide permissions, or call the API.
* Reusable widgets go in `lib/widgets/` only once a second feature actually
  needs them. Do not pre-build a component library.
* Models mirror Laravel API Resources exactly. A model that invents a field the
  backend does not send is a bug.
* Keep `ApiClient` ignorant of endpoints. It transports; it does not know what
  a listing is.
* Follow the backend's own layering discipline (Controller → Request → Service
  → Repository → Resource) rather than inventing a Flutter-specific equivalent
  of it. On the client the useful cut is: widget → repository/service → model →
  HTTP.
* Compose long-lived dependencies in `main.dart` only.

---

## B. API

**The Laravel REST API in `backend/` is the source of truth.**

* **Do not invent endpoints.**
* **Do not invent response fields.**
* Use the existing API contracts. Read the controller and the Resource before
  writing a model.
* Never hard-code a URL. All base URLs resolve through `AppConfig`.
* All HTTP goes through `ApiClient`. Do not create a second client, and do not
  call `dart:io` or `package:http` directly from a feature.
* Token handling is centralised in `ApiClient` + `TokenStore`. Do not add
  per-request token logic.

### Response envelope

Controllers return:

```json
{ "success": true, "message": "...", "data": { } }
```

`ApiClient` unwraps `data`, so feature code never writes `json['data']`. See
`lib/models/api_envelope.dart`.

### Conventions that will bite you if you ignore them

These are verified against the Laravel implementation. Follow them.

| Concern | Reality | Consequence |
|---|---|---|
| Money | `decimal` columns serialised as **strings** (`asking_price`, `total_amount`) | Keep as `String` in the model. Format at the edge. Never `int`/`double` round-trip in the model. |
| Dates | ISO-8601 UTC strings | Parse once in `fromJson`, via `readDateTime`. |
| Nullable columns | Present as `null`, not absent | Model as `T?`, not optional `T?`. |
| Enums | Lowercase string values from PHP backed enums | Match exactly: `role` `user`/`admin`; `seller_capability` `buyer`/`seller`; verification `submitted`/`pending_review`/`approved`/`rejected`; listing `draft`/`pending`/`active`/`sold`/`inactive`; transaction `pending`/`completed`/`cancelled`. |
| Pagination | **Not** Laravel's `LengthAwarePaginator`. A hand-rolled `pagination` object: `{current_page, last_page, per_page, total}` | Use `lib/models/pagination.dart`. |
| List keys | Endpoint-specific: `listings`, `users`, `transactions`, `verifications`, `activities` | Parse per endpoint. Do not generalise. |
| Identifiers | Auto-increment ints — **except** `notifications.id`, a UUID string | Do not route notification ids through `readInt`. |
| Errors | `422` carries per-field `errors` | Read via `ApiException.validationErrors`. |

`lib/core/utils/json_utils.dart` exists so this parsing happens one way. Use it
instead of hand-rolling casts.

### Security requirements — BINDING

These are approved requirements, not suggestions. Full text in
`docs/AGROBENTA_FUNCTIONAL_DOCUMENTATION.md` §10; contract view in
`docs/MOBILE_API_CONTRACT_PROPOSAL.md` §4.5 and §6.2.

**The client must never send these fields.** The server rejects them with `422`;
sending one is a client bug, and "the server ignores it" is not an excuse.

| Field | Why it must never be sent |
|---|---|
| `seller_capability` | Server-side only. Sending `"seller"` is an attempt to bypass seller verification. |
| `role` | Server-side only. |
| `seller_id` (listings) | Ownership is the authenticated user. |
| `buyer_id` / `seller_id` (transactions) | Derived server-side. |
| `sender_id` (messages) | The authenticated user. |
| `total_amount` | Server-computed from the listing. |
| `status` (listings) | **Not settable by a seller at all** — see "Listing publication" below. |

Build request bodies from an **explicit allow-list** of fields, never by passing
a whole form map through. A field added to a model on the server must not
silently become client-settable.

**Seller capability comes from `GET /auth/me` and from the verification flow
only.** The client renders "Become a Seller" from
`seller_capability == 'buyer'` and never sets it.

### Listing publication

Lifecycle: `draft → pending → active → sold`, plus `pending → inactive` and
`active → inactive`. A seller **cannot** set `active`.

| Status | Buyer marketplace | Own listings screen |
|---|---|---|
| `draft` | hidden | visible |
| `pending` | hidden | visible — "awaiting review" |
| `active` | **visible** | visible |
| `sold` | not listed | visible |
| `inactive` | hidden | visible |

* Creating a listing produces `draft`. **The app sends no `status`.**
* Submission is a **separate action** (`POST /seller/listings/{id}/submit`),
  not a field. Show "Submit for review" on a `draft`.
* "Awaiting review" is the label for `pending`. Do not show a draft or pending
  listing as purchasable.
* Only `active` listings show a "contact seller" / "buy" affordance.
* A rejected listing becomes `inactive`. **There is no path back to `active`**
  from the current backend, and no reactivation endpoint — do not render a
  "Reactivate" or "Republish" control.
* Photos: the API exposes them; the **database schema does not change** to make
  that happen.

### Resources are not shared with the Admin Web

**Do not expect seller email addresses.** Marketplace listing responses carry
only marketplace-appropriate seller fields (id, display name). The Admin Web
resources are admin-oriented and are not reused for mobile.

If a model needs a seller email, that is a bug in the contract, not a missing
field on the client. Do not add a field to a mobile model that the mobile API
does not send.

---

## C. Authentication

* **Laravel Sanctum personal access tokens.**
* Send `Authorization: Bearer <token>`. `ApiClient` does this for you.
* Preserve the existing backend authentication. Do not weaken or bypass it.
* **Do not introduce Firebase Authentication.**
* **Do not create a second authentication system.** No OAuth layer, no custom
  token format, no client-side session authority.
* Tokens are stored in the platform keystore via `flutter_secure_storage`
  (`TokenStorage`). Do **not** move the token to `shared_preferences` — that is
  unencrypted storage for a bearer credential.
* The Admin Web keeps its token in `localStorage`. Do not copy that. It is
  acceptable for a browser tab; it is not acceptable on a user's phone.
* A `401` clears the stored token in `ApiClient`. Treat
  `ApiException.requiresReauthentication` as the signal to return to the
  sign-in flow. Do not retry a request with a revoked token.
* Sanctum tokens currently have **no expiry** and there is no refresh flow.
  See GAP-15. Do not invent a client-side expiry policy without agreement.

---

## D. Single-account model

There is **one** account per person. The account does not change when the user
becomes a seller.

```text
registration ──> buyer                (seller_capability = 'buyer')
                     │
                     │ "Become a Seller"
                     ▼
              seller verification     (status = submitted)
                     │
              admin reviews
                     ▼
              approved ──> seller     (seller_capability = 'seller')
```

Every registered user starts as a **buyer**.

A user may choose to **Become a Seller** by submitting seller verification.
Verification states, exactly as implemented in
`backend/app/Enums/SellerVerificationStatus.php`:

| State | Meaning |
|---|---|
| `submitted` | Submitted by the user, not yet picked up |
| `pending_review` | Under admin review |
| `approved` | Approved — seller capabilities are granted |
| `rejected` | Rejected — `admin_note` explains why |

**Only an approved seller has seller capabilities.** The backend flips
`seller_capability` to `seller` on approval
(`AdminSellerVerificationService`). The mobile app reflects that state; it does
not grant capabilities itself.

**A user cannot become a seller by editing their own account.** The app never
sends `seller_capability` or `role` in any request. The only path to seller
capability is: submit verification → admin approves → the server sets the field.
`PATCH /profile` rejects both fields.

### Never do this

* Do not create a separate buyer account and a separate seller account.
* Do not add a "Switch to Seller" toggle.
* Do not treat being a seller as a different login, a different token, or a
  different user id.
* Do not let the client decide what a seller may do. The server decides; the
  client renders the consequence.

`seller_capability` is not a UI-only flag. Gate seller UI on it, and expect the
server to reject seller actions from a non-approved seller regardless.

---

## E. Backend safety

* **Never bypass authorization.** Do not add a client-side shortcut that assumes
  the server will not check.
* A seller may manage **only their own listings**. Scope every seller listing
  request by the authenticated user. Never trust a `seller_id` supplied by the
  device.
* Administrative functions remain in the Admin Web. Admin endpoints live under
  `/api/admin/*` and are guarded by the `admin` middleware. **This app must not
  call them.**
* Do not create an admin mobile app, an admin role check, or an admin screen.
* Do not modify the backend without explicit approval. If mobile needs something
  the API does not provide, record it in the **API Gap register** below and
  stop. Do not implement it in the backend to unblock yourself.
* Never commit secrets, API keys or tokens. Base URLs are configuration, not
  secrets, but still belong in `--dart-define`, not in source.

---

## F. Development

* Reuse what exists before adding. This project is new, but it will not stay
  that way — check for an existing widget, service or model first.
* Avoid duplicate architecture. Two API clients, two token stores, or two
  pagination models in one app is a defect.
* Avoid unnecessary dependencies. Before adding a package, confirm the platform
  or Flutter SDK cannot do it, and be able to say what it is for.
* Validate before reporting completion:

  ```sh
  flutter pub get
  flutter analyze          # must be clean
  flutter test             # must pass
  flutter build apk --debug
  ```

* Write tests where they earn their keep. Priority order:
  1. model `fromJson` against the real Resource shape,
  2. service request shape (method, path, body, query),
  3. widget behaviour for reusable widgets.
* Do not weaken a test to make it pass.
* Do not use `print` for diagnostics; use `debugPrint` or a logger.
* Do not commit build output. `mobile/.gitignore` already covers it.
* Keep documentation accurate. If behaviour, setup, commands or architecture
  change, update this file, `mobile/DESIGN.md` or the gap register.

### Current dependencies

| Package | Why it exists | Do not replace with |
|---|---|---|
| `http` | The single HTTP layer behind `ApiClient`. Chosen over `dio` to keep the dependency surface minimal; the one thing `dio` gave us — interceptors — is handled inside `ApiClient`. | A second client, or raw `dart:io`. |
| `flutter_secure_storage` | Sanctum bearer token in the Android Keystore / iOS Keychain. | `shared_preferences` (unencrypted). |
| `flutter_lints` | Analyzer baseline, via `analysis_options.yaml`. | — |
| `intl` | Peso, date and relative-date formatting in `AppFormatters`, added in M2 as the first screen that displays money. `main()` calls `initializeDateFormatting('en_PH')` before the first frame; **any locale other than `en_US` must be initialised or `DateFormat` throws**, and `test/flutter_test_config.dart` does the equivalent for the suite. | Hand-rolled month names or a second date library. |
| `cupertino_icons` | Scaffold default. Currently unused by app code; remove it if it stays unused when real iOS-styled widgets land. | — |

**Deliberately not added** in M0, and the phase that should justify each:
state management (M1+), routing (`go_router`, M1), `intl` for peso/date
formatting (first screen that displays money — added in M2), image handling
(marketplace), location, database, Firebase. Adding any of these early is scope
creep.

**Image handling is still not a dependency.** GAP-06 has no URL scheme, so
`ListingPhoto` uses the SDK's `Image.network` and only for a value that is
already an absolute `http`/`https` URL; anything else is a placeholder. There is
nothing to cache or manage until photos are actually fetchable, so
`cached_network_image` is not justified yet.

---

## G. Local development

The backend runs in Docker. Laravel is served by Nginx on
**`http://localhost:8001`**, API under `/api`.

### The Android emulator rule

**Android emulator → host machine is `10.0.2.2`.**

The emulator sits behind a virtual network bridge, so `localhost` inside it is
the emulator itself, not your development machine. Code that works on the iOS
simulator will fail on Android if it uses `localhost`.

| Where the app runs | Base URL to use |
|---|---|
| Android emulator | `http://10.0.2.2:8001/api` |
| iOS simulator | `http://localhost:8001/api` |
| Physical device (same Wi-Fi) | `http://<your-LAN-IP>:8001/api` |
| Staging / production | `https://…/api` |

`AppConfig.apiBaseUrl` already resolves the first two rows per platform.

### Never scatter URLs

`AppConfig` is the only place a base URL is defined. Override per build:

```sh
# Android emulator (this is already the default)
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8001/api

# Physical device on the same network
flutter run --dart-define=API_BASE_URL=http://192.168.1.20:8001/api

# Staging
flutter run --dart-define=API_BASE_URL=https://api.staging.example.test/api
```

`API_BASE_URL` is the single canonical name. Do not introduce a second spelling
for the same value. (The Admin Web has exactly this bug: `lib/api.ts` reads
`VITE_API_URL` while `vite-env.d.ts` declares `VITE_API_BASE_URL`. Do not
reproduce it.)

### Android cleartext traffic

`android/app/src/main/res/xml/network_security_config.xml` denies cleartext by
default and permits it **only** for `10.0.2.2`, `localhost` and `127.0.0.1`.
That is a development allowance. Production must be HTTPS. If a staging host
cannot serve TLS, add it there explicitly with a comment — never flip the
base config to `true`.

The main `AndroidManifest.xml` declares `android.permission.INTERNET`. The
`debug` and `profile` manifests also declare it, but those are not merged into
a release build, so the main manifest must keep it.

---

## H. Scope discipline

Implement **only** the phase you were asked for.

* Do not build a later phase's screens "while you are in there".
* Do not add a dependency for a feature that does not exist yet.
* Do not create feature folders, models or services in anticipation.
* Do not wire up navigation to screens that have not been built.
* Preserve compatibility with planned future phases, but do not build them.
* If you notice a problem outside your phase, **report it**; do not fix it
  unasked. Backend problems go in the gap register, not into a commit.

---

## API Gap register

**Resolved for M1 (auth).** The backend now exposes a mobile authentication API
behind `auth:sanctum` + `ability:mobile`:

| Endpoint | Purpose |
|---|---|
| `POST /api/auth/register` | Creates a buyer and returns a mobile token. |
| `POST /api/auth/login` | Returns a mobile token. `403` for administrators. |
| `GET /api/auth/me` | The current user, as a `UserResource`. |
| `POST /api/auth/logout` | Revokes the calling mobile token. |

Mobile tokens are issued with `createToken('mobile', ['mobile'])` and are
refused by the `admin` group, which additionally requires `ability:admin`. The
role and the seller capability are assigned by the server; the client never
sends them. See `docs/MOBILE_API_CONTRACT_PROPOSAL.md` for the agreed contract.

One contract detail to keep in mind: **`POST /api/auth/logout` returns
`{ success, message }` with no `data` key.** `ApiClient` normalises a valid
success envelope that omits `data` to `data: null`; `ApiEnvelope` itself stays
strict and still rejects a missing `success`.

**Resolved for M2 (marketplace browse).** The backend now exposes a read-only
buyer marketplace behind the same `auth:sanctum` + `ability:mobile` guard:

| Endpoint | Purpose |
|---|---|
| `GET /api/listings` | One page of `active` listings, with search, filters and pagination. |
| `GET /api/listings/{listing}` | One listing's detail. Answers `404` for anything not visible to the caller. |

Both accept only the query keys `search`, `livestock_type`, `location`,
`min_price`, `max_price`, `page` and `per_page`; `per_page` is capped at 50. The
list is `active`-only and ordered `created_at DESC, id DESC`. A non-active
listing, one owned by another seller, and one that never existed are all `404`
by design, so listing existence is not disclosed — the app renders a single
"no longer available" state for all three. `GET /admin/listings` is **not** used
by the app; it is admin-only and returns seller fields the marketplace must not
expose.

**Still open below.** GAP-01 to GAP-05, GAP-07, GAP-08 and GAP-16 are `CLOSED` —
implemented in the backend and consumed by the app. GAP-06 is narrowed but not
closed. Everything from GAP-09 onwards is unchanged and still blocks its phase.

Status: `CLOSED` = implemented. `OPEN` = does not exist. Nothing open here has
been worked around in the app.

| ID | Gap | Backend evidence | Blocks |
|---|---|---|---|
| GAP-01 | Mobile login for non-admin users | **CLOSED.** `POST /api/auth/login` (`routes/api.php`) with `Api/Auth/AuthController@login` and `MobileAuthService`. Administrators are refused with `403`. | — |
| GAP-02 | Registration endpoint | **CLOSED.** `POST /api/auth/register` with `Api/Auth/RegisterRequest`; the server fixes `role=user` and `seller_capability=buyer`. | — |
| GAP-03 | Current-user endpoint for non-admins | **CLOSED.** `GET /api/auth/me` returns a `UserResource` in the standard envelope. | — |
| GAP-04 | Logout for non-admins | **CLOSED.** `POST /api/auth/logout` revokes the calling mobile token. | — |
| GAP-05 | Marketplace browse (list/detail/filter/paginate) | **CLOSED.** `GET /api/listings` and `GET /api/listings/{listing}`, served by `Api/Marketplace/MarketplaceController` over `MobileListingResource` (seller narrowed to `id` + `name` by `MobileSellerResource`). `active`-only list; `404` for any non-visible listing. | — |
| GAP-06 | Listing photo delivery | **NARROWED, still `OPEN`.** `MobileListingResource` now returns the `listings.photos` column as a flat list of strings, so the client receives the stored values. But there is still no upload endpoint, no storage disk bound to the column, and no agreed URL scheme, so those values are storage-relative paths such as `listings/1/front.jpg`, not fetchable URLs. The app renders a placeholder for any value that is not already an absolute `http`/`https` URL and must not synthesise a base URL. | Listing management |
| GAP-07 | Seller verification submission | **CLOSED.** `POST /api/seller-verification` (`routes/api.php`) with `Api/SellerVerification/SellerVerificationController@store` and `SellerVerificationService`. Creates a `submitted` record; **grants no capability** — `seller_capability` is still written only by the admin approval endpoint. A second submission while one is `submitted`/`pending_review` is `409`; an approved seller is `403`; a rejected record may be resubmitted as a new row. `SubmitSellerVerificationRequest` allow-lists the four client fields and rejects server-owned ones with `422`. Deliberately **unthrottled** — see D-09. | — |
| GAP-08 | Own verification status retrieval | **CLOSED.** `GET /api/seller-verification/me` with `MobileSellerVerificationController@me`, returning the caller's latest record by `submitted_at DESC, id DESC` through `MobileSellerVerificationResource` (omits `seller`, `reviewer`, `user_id`, timestamps). `404` when the caller has never applied, which the app reads as "not submitted" rather than as an error. No route takes an id, so one buyer cannot read another's record. | — |
| GAP-09 | Seller listing CRUD, own listings only | No create/update/delete/publish route for sellers. `ListingsTab` is read-only in the Admin Web. `OPEN`. | Listing management |
| GAP-10 | AI price suggestion | `AiPriceEstimate` model and `ai_price_estimates` table exist. No controller, service, route or job. No pricing algorithm in the repository. `OPEN`. | AI price suggestion |
| GAP-11 | Transactions | `GET /admin/transactions` only. No buyer view, seller view, creation, or status transition. `OPEN`. | Transactions |
| GAP-12 | Notifications | `notifications` table exists (standard Laravel, **UUID** primary key). No `Notification` model, no `NotificationResource`, no route. `OPEN`. | Notifications |
| GAP-13 | Messaging | `Message` model and `messages` table exist. No `MessageResource`, no controller, no route. Dead schema. `OPEN`. | Messaging |
| GAP-14 | Profile read/update for the current user | No endpoint. Admin can list users but not edit them. `OPEN`. | Profile |
| GAP-15 | Token lifetime policy | Mobile tokens are issued non-expiring, the same as admin tokens. No expiry, no refresh, no revocation-all. Still needs an explicit decision before shipping, so a mobile session currently lasts until it is logged out or revoked. | Security |
| GAP-16 | Sanctum token ability scoping for mobile | **CLOSED.** Mobile tokens carry `['mobile']`; mobile routes require `ability:mobile`. The `admin` group now also requires `ability:admin`, so a mobile token is refused by admin routes and an admin token is refused by mobile routes. Both directions are covered by `backend/tests/Feature/Auth/MobileAuthTest.php`. | — |

### Gaps that are design questions, not missing code

Report these; do not decide them unilaterally.

* **`livestock_type` is free text.** `listings.livestock_type` is a plain
  `string` with an index but no enum and no validation list. Mobile needs a
  controlled vocabulary for filter chips and pickers. Where should that list
  live — a backend enum, an endpoint, or app constants? This is a
  business-rule question.
* **Currency and locale.** The Admin Web formats as `₱` / `en-PH`. The schema
  has no currency column. Assume PHP peso until told otherwise, and centralise
  the formatter so it is a one-line change.
* ~~No approved functional documentation exists~~ — **closed.** The approved
  functional documentation now lives at
  `docs/AGROBENTA_FUNCTIONAL_DOCUMENTATION.md`. It was approved during planning
  but was never committed, which is why this gap existed. One residual item
  remains: the planning original is still not stored in the repository (DG-01
  there).

---

## Mobile API contract — **see `docs/MOBILE_API_CONTRACT_PROPOSAL.md`**

An abbreviated contract was drafted inline here during M0. It has since been
**superseded** by the full proposal at
`docs/MOBILE_API_CONTRACT_PROPOSAL.md`, which specifies every endpoint across all
ten required dimensions and carries the open-decision register. **Use that
document, not this section.** The inline copy is kept only as a record of what
M0 proposed.

**Business rules are now finalized** (D-02 listing publication, D-03 price
suggestion, D-15 transaction status, and the security requirements). They are
approved and locked in `docs/AGROBENTA_FUNCTIONAL_DOCUMENTATION.md`, which
**outranks** the proposal and this file. The proposal has been updated to match.

Nothing may be built against the contract until the backend actually serves
those routes. Laravel is authoritative; if the real implementation differs, the
implementation wins and the documents get corrected.

The M0 endpoint set, unchanged except where D-02 replaced seller-set `status`
with a submit action:

```
POST   /auth/register
POST   /auth/login
GET    /auth/me              auth:sanctum
POST   /auth/logout          auth:sanctum
GET    /listings             ?search&livestock_type&page&per_page
GET    /listings/{id}
POST   /seller-verification
GET    /seller-verification/me
GET    /seller/listings
POST   /seller/listings
POST   /seller/listings/{id}/submit     (new — D-02)
PATCH  /seller/listings/{id}
DELETE /seller/listings/{id}
```

AI price suggestion, transactions, notifications, messaging and profile were
deliberately left unscoped in M0. They are now specified in the proposal, still
subject to GAP-10 through GAP-14, GAP-17, and the open decisions recorded
there.

### New findings from the contract review

The review surfaced backend issues that were **not** in the M0 register. Full
detail and evidence in `docs/MOBILE_API_CONTRACT_PROPOSAL.md` §7. The two that
most affect any mobile work are now **approved requirements** (functional
documentation §10), not open questions:

* **`role` and `seller_capability` are mass-assignable** — `#[Fillable]`
  includes both (`User.php:17`), as do `Listing.seller_id`,
  `Transaction.buyer_id`, `Transaction.seller_id` and `Message.sender_id`. A
  request class that passes these through lets a device set its own
  `seller_capability` to `seller` and bypass seller verification. Every mobile
  write endpoint needs an explicit field allow-list. See "Security
  requirements" above.
* **`ListingResource` embeds `seller.email`** (also `TransactionResource` and
  `SellerVerificationResource`). Those are administrator views; reusing them on
  mobile would hand every seller's email address to every marketplace reader.
  Admin resources stay admin-oriented; mobile gets its own public projections.

### Gap register changes from the decision round

Listing publication (D-02) and transaction status (D-15) are now **decided**.
The register entries change accordingly:

| Gap | Change |
|---|---|
| **GAP-06** photos | Constrained: **no schema change** is permitted to expose photos. The mobile API must expose them; the representation is still undecided. |
| **GAP-09** seller listing CRUD | A seller **cannot** set `status`. Create yields `draft`; a separate `submit` action moves it to `pending`. |
| **GAP-10** AI price suggestion | The endpoint and service boundary are specified. The **estimation method is still undecided** and must not be invented. Do not render a suggestion UI that implies a computed value before the service exists. |
| **GAP-11** transactions | Lifecycle decided: `pending → completed \| cancelled`, both terminal. Cancellation by either party is implementable; **completion is blocked** — the confirming actor is undecided. |
| **GAP-17** *(new)* admin listing moderation | **Required by D-02 but does not exist.** Admin can only read listings. Until `approve`/`reject`/`deactivate` exist, no listing can legitimately become `active`. |
| **GAP-18** *(new)* seller cannot self-publish | A seller-side `status` field would violate D-02 rule 6. The app must send no `status` and use the submit action. |

---

## Change safety

* Do not delete, rename or replace existing files, routes, screens, widgets or
  services unless the current task requires it and it is approved.
* Do not remove something because it looks unused. Unused foundation code is
  cheaper than a broken app.
* Avoid unrelated refactoring.
* Report anything you notice but were not asked to change.

## Git safety

* Do not commit, push, reset, rebase or force-push unless explicitly asked.
* Never discard existing user changes. (`frontend/src/index.css` had
  uncommitted changes as of M0 — leave it alone.)
* Report the exact files you changed.

## Validation before reporting

```sh
flutter pub get
flutter analyze     # must be clean
flutter test        # must pass
flutter build apk --debug
```

Never claim a command succeeded without having run it. If a command cannot run,
say so and say why.
