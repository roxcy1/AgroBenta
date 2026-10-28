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
3. **The capstone manuscript** (final document, PDF outside the repository) as
   restated in `docs/AGROBENTA_FUNCTIONAL_DOCUMENTATION.md`. The manuscript's
   prototype screens are part of it.
4. Backend API implementation and contracts (`backend/routes/api.php`,
   controllers, requests, resources, services, repositories, models,
   migrations) — the actual behaviour wins over any assumption
5. This file
6. `mobile/DESIGN.md` (mobile-specific visual rules only)
7. Existing Flutter code in `mobile/`

Consequences:

* **Business rules** come from the manuscript, as restated in
  `docs/AGROBENTA_FUNCTIONAL_DOCUMENTATION.md`. Where it is silent or lists the
  point as open (§13 there), **stop and report** — do not invent a rule. Do not
  edit that document to match the code; see `docs/AGENTS.md`.
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
* Do not treat being a seller as a different login, a different token, or a
  different user id.
* Do not let **Seller Mode / Buyer Mode** grant anything. The Account Mode
  switch (manuscript Figure 20; functional documentation §2.7) is a **view**
  switch only: Seller Mode is offered only when the server reports
  `seller_capability = seller`, switching sends no request that changes `role`
  or `seller_capability`, and the selected mode is cleared on logout.
* Do not let the client decide what a seller may do. The server decides; the
  client renders the consequence.

`seller_capability` is not a UI-only flag. Gate seller UI on it, and expect the
server to reject seller actions from a non-approved seller regardless.

### Account Mode shells

`AccountModeShell` replaces the whole signed-in destination when the mode
changes; it does not push another screen. It guards Seller Mode both ways: the
controller refuses to select it without server-granted seller capability, and
the shell falls back to `BuyerShell` if the selected mode and capability
disagree. Signing out, changing accounts or losing capability clears the mode.

* **BuyerShell** keeps Home, Browse, Messages, Transactions, Profile. Its
  Transactions screen is **My Purchases** and sends `role=buyer`.
* **SellerShell** has Home, My Listings, Messages, Transactions, Profile. Its
  Transactions screen is **My Sales** and sends `role=seller`. My Listings is a
  real tab here; the buyer Home entry card still switches to it through
  `SellerListingsEntryCard.onManage` instead of pushing a duplicate screen.
* **Seller Home** is the seller landing and token-scoped summary: the account
  greeting, notification bell, real listing/inquiry/transaction counts, My
  Listings entry, Profile action and a link to Received Inquiries. The counts
  come from `GET /seller/dashboard`; no revenue, conversion, completed-sales or
  other fabricated metric is shown. `transactions.total` is the number of the
  seller's transaction records, not a count of completed sales. Received
  Inquiries is a pushed screen, not a sixth tab, and shows the seller's own
  `GET /seller/inquiries` records. The list is read-only in this phase;
  responding to or re-statusing an inquiry remains unavailable (GAP-19).

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
| `font_awesome_flutter` | Provider brand marks for the registration and login screens' (disabled) Google and Facebook buttons. Material has no Google glyph and the project ships no brand assets, so `FaIcon(FontAwesomeIcons.google/facebook)` is the only accurate source. Pin `^11.0.0`: earlier 10.x versions extend `IconData`, which this SDK declares `final`, and fail to compile. | A hand-drawn `CustomPainter`, an SVG asset, or a second icon-font package. |
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

### The Android address rule

**The default Android target is a physical device → the machine's LAN IP.**

A real phone cannot reach the host through the emulator loopback alias
`10.0.2.2` (that address exists only inside an Android emulator). The emulator
sits behind a virtual network bridge, so `localhost` inside it is the emulator
itself, not your development machine.

| Where the app runs | Base URL to use |
|---|---|
| Android — physical device (same Wi-Fi) | `http://<your-lan-ip>:8001/api` (**the default**) |
| Android — emulator | `http://10.0.2.2:8001/api` (opt in with `ANDROID_RUN_TARGET=emulator`) |
| iOS simulator | `http://localhost:8001/api` |
| Chrome / Edge (Flutter Web) | `http://localhost:8001/api` (already the default) |
| Staging / production | `https://…/api` |

`AppConfig.apiBaseUrl` already resolves this per platform. The address in
`<your-lan-ip>` is this development machine's LAN IP
(flagged `CHANGE_THIS_DEV_LAN_IP`); update it if the machine's IP ever changes.

### Never scatter URLs

`AppConfig` is the only place a base URL is defined. Choose the Android target
and override per build:

```sh
# Physical device (default, no flag needed)
flutter run

# Android emulator — explicit opt-in to the 10.0.2.2 host alias
flutter run --dart-define=ANDROID_RUN_TARGET=emulator

# Point anywhere explicitly
flutter run --dart-define=API_BASE_URL=https://api.staging.example.test/api
```

`API_BASE_URL` is the single canonical name for the URL. `ANDROID_RUN_TARGET`
only chooses between the two built-in Android defaults and must be `emulator`
to yield the host alias; any other value is a physical-device build, so a
physical build can never silently fall back to `10.0.2.2`. Do not introduce a
second spelling for `API_BASE_URL`. (The Admin Web has exactly this bug:
`lib/api.ts` reads `VITE_API_URL` while `vite-env.d.ts` declares
`VITE_API_BASE_URL`. Do not reproduce it.)

### Android cleartext traffic

Debug builds allow plain HTTP broadly via
`android/app/src/debug/res/xml/network_security_config.xml` — that is the only
reason a phone on the LAN can reach the plain-HTTP Docker stack. The main
config (`android/app/src/main/res/xml/network_security_config.xml`) stays
strict: it denies cleartext by default and permits it **only** for `10.0.2.2`,
`localhost` and `127.0.0.1`. That is a development allowance. Production must be
HTTPS. If a staging host cannot serve TLS, add it to the main config explicitly
with a comment — never flip the base config to `true`.

The main `AndroidManifest.xml` declares `android.permission.INTERNET`. The
`debug` and `profile` manifests also declare it, but those are not merged into
a release build, so the main manifest must keep it.

### Flutter Web (development target)

The repository has a configured Flutter web target: `web/` exists, `.metadata`
lists `web`, and `flutter build web` succeeds. It is a **development and
browser-verification target** — not a claim that the web build is a shipped
client, and not evidence that a browser flow has been verified.

* `backend/config/cors.php` allows `http://localhost:8080`, the default port of
  `flutter run -d chrome`. Starting the dev server on another port with
  `--web-port` requires adding that origin there too, or the browser refuses
  the response.
* `AppConfig` resolves web to `http://localhost:8001/api` from `kIsWeb`; it
  deliberately does not trust the browser's user agent.
* Photo picking uses `image_picker`, which has web support, and local previews
  read `XFile` bytes through `LocalImagePreview` instead of `Image.file`, so the
  composer does not depend on `dart:io`.
* Token storage uses `flutter_secure_storage`'s web backend, which is browser
  storage — not the Android Keystore or iOS Keychain. Do not describe web token
  storage as equivalent to the native platforms.
* Windows and Linux desktop are **not** configured targets: there is no
  `windows/` or `linux/` runner in this repository.
* A successful build proves compilation only. Sign-in, listing submission,
  photo upload and CORS round trips still need manual browser verification
  before any flow is reported as working on web.

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

**Resolved for the Inquire screen (buyer inquiries).** The backend now exposes
one write endpoint behind the same `auth:sanctum` + `ability:mobile` guard:

| Endpoint | Purpose |
|---|---|
| `POST /api/inquiries` | Files one buyer inquiry against an `active` listing. Returns `201` with the `MobileInquiryResource` and the envelope message `Inquiry sent.`. |

The body allow-list (`StoreInquiryRequest`, mirrored by
`InquiryEndpoints.writableFields`) is exactly `listing_id`, `message`,
`subject`, `purchase_interest`, `transaction_method`, `delivery_method`,
`delivery_fee`, `contact_method` and `preferred_schedule`; `buyer_id`,
`seller_id` and `status` are rejected with `422` (see the security
requirements above — the app builds the body from the allow-list only).
`InquiryService` answers `409` for a non-active listing and `409` for the
caller's own listing, and `404` when the listing does not exist. Creating an
inquiry changes nothing else: no transaction, no listing status change, no
notification. Triage and re-status live under `/api/admin/inquiries*` and are
not called by this app.

The **Inquiry Sent** confirmation is rendered entirely from that create
response — the record it returns is the screen's single source of truth, and
its status card is a fixed, honest sentence, never a fetched or modelled
server status. There is still no buyer endpoint to re-read an inquiry (GAP-19),
so "View Inquiry" ships disabled with an honest caption rather than faking a
route.

**Resolved for the Seller Home dashboard (HTTP only).** The backend exposes a
token-scoped summary behind the same `auth:sanctum` + `ability:mobile` guard
plus the `seller` gate:

| Endpoint | Purpose |
|---|---|
| `GET /api/seller/dashboard` | Aggregated listing, inquiry and transaction counts for the authenticated seller. |

The response `data` shape is:

```json
{
  "listings": {
    "total": 6,
    "draft": 1,
    "pending": 1,
    "active": 2,
    "sold": 1,
    "inactive": 1
  },
  "inquiries": { "total": 3 },
  "transactions": { "total": 4, "pending": 2 }
}
```

`SellerDashboardRequest` accepts no filter, ownership or status input;
`buyer_id`, `seller_id`, `user_id`, `role` and `status` are `422`. Every query
is scoped to `$request->user()` in repository SQL, so no client value can widen
the result to another seller's records. `listings.total` is derived from all
five status buckets; `transactions.total` counts the seller's transaction
records and is **not** a completed-sales figure. There is no revenue,
conversion, completion-rate or historical metric, and transaction completion
remains unavailable (OQ-15). Seller Home renders loading, empty, error/retry and
refresh-failure states from real responses; the summary cards navigate to the
existing My Listings tab, Received Inquiries screen and Transactions tab. The
shell still has exactly five destinations. Backend coverage lives in
`backend/tests/Feature/SellerDashboard/SellerDashboardTest.php`.

**Resolved for the Received Inquiries screen (seller inbox, HTTP only).** The
backend exposes the approved seller's own inbox behind the same
`auth:sanctum` + `ability:mobile` guard plus the `seller` gate:

| Endpoint | Purpose |
|---|---|
| `GET /api/seller/inquiries` | One paginated page of inquiries whose listing belongs to the caller (`?page`, `?per_page`; `per_page` capped at 50). |

`IndexSellerInquiryRequest` accepts only `page` and `per_page`; `buyer_id`,
`seller_id` and `status` are `422`. The scope is always the token, applied in
the repository SQL, so no request can widen the result to another seller's
inbox. `SellerInquiryResource` carries `id`, `buyer{id,name}` (or null),
`listing{id,livestock_type,breed}` (or null after deletion), `subject`,
`message`, `purchase_interest`, `transaction_method`, `delivery_method`,
`delivery_fee`, `contact_method`, `preferred_schedule` and `created_at`. It
deliberately omits `status`, the seller, and every buyer contact detail,
including email.

Seller Home links to `ReceivedInquiriesScreen`; the shell still has exactly five
destinations. The screen loads the first page, supports pull-to-refresh and
load-more, and renders loading, empty, error/retry and refresh-failure states
from real responses. It shows no status badge and no response control, because
no seller response or inquiry-detail endpoint exists. A null buyer is rendered
as "Unknown buyer" and a null listing as "Listing no longer available"; neither
is fabricated. The repository clamps `per_page` to `1..50` and normalises a page
below 1, the same policy the transactions list uses.

**Resolved for the Messages screen (inbox + chat, HTTP only).** The backend
exposes the caller's own conversations and messages behind the same
`auth:sanctum` + `ability:mobile` guard:

| Endpoint | Purpose |
|---|---|
| `GET /api/conversations` | The caller's conversation list. A conversation is derived from message pairs — there is no `conversations` table and no conversation id. |
| `POST /api/conversations/{userId}/read` | Marks the caller's unread messages in the thread with `userId` (optional `listing_id`) and returns `{updated}`. |
| `GET /api/conversations/{userId}/messages` | One paginated `messages` page for the thread with `userId` (`?listing_id`, `?page`, `?per_page`). |
| `POST /api/messages` | Sends one message. The sender is the authenticated user; `sender_id` is never sent. |
| `PATCH /api/messages/{id}/read` | Marks one message read. |

`ConversationResource` carries `counterpart{id,name,avatar_url}`, `listing_id`,
`listing_title`, `last_message`, `last_message_at` and `unread_count`;
`MessageResource` carries the message plus embedded sender/receiver summaries.
The app's `Conversation` and `Message` models mirror them exactly. Search and
the category chips are **local view filters** — the API has no conversation
search and no category column. "Inquiries" selects listing-scoped threads;
"Transactions" renders disabled — the API links no conversation to a
transaction, and My Purchases / My Sales are separate screens over
`/api/transactions`;
"Notifications" is a shortcut to the existing, separate notifications
destination, not a thread filter. Opening a thread marks it read through the
same endpoint from two callers by design (the inbox optimistically, the chat
screen on open). **There is no real-time transport** (GAP-20): the inbox and
thread recover via pull-to-refresh and an on-return refresh, and the app ships
no WebSocket client, no invented event names and no fake reconnect.

**Resolved for the Transactions screens (My Purchases / My Sales, HTTP only).**
The backend exposes the caller's transactions behind the same `auth:sanctum` +
`ability:mobile` guard:

| Endpoint | Purpose |
|---|---|
| `GET /api/transactions` | One paginated page of the caller's own transactions (`?role`, `?status`, `?page`, `?per_page`; `per_page` capped at 50). |
| `POST /api/transactions` | Creates a `pending` transaction as the authenticated buyer. The body allow-list is exactly `listing_id`, `quantity`. |
| `GET /api/transactions/{id}` | One transaction the caller is party to; `404` for missing and foreign records alike. |
| `POST /api/transactions/{id}/cancel` | Cancels a `pending` transaction (either party); `409` once terminal. The body allow-list is empty. |
| `POST /api/transactions/{id}/complete` | **Not implemented** — answers `501` (OQ-15). The client ships no completion affordance. |

`IndexTransactionRequest` accepts only `role` (`buyer`/`seller`), `status`
(`pending`/`completed`/`cancelled`), `page` and `per_page`; `buyer_id` and
`seller_id` are `422`. `MobileTransactionResource` carries `id`, `role` (the
viewer's side), `listing{id,livestock_type,breed,photos}`,
`counterparty{id,name,email}`, `quantity`, `total_amount` (server-derived
`asking_price × quantity`, a decimal **string**), `status`, `created_at` and
`updated_at`. There is **no location field**, so the card shows none.

Buyer Mode's **My Purchases** always sends `role=buyer`; Seller Mode's **My
Sales** always sends `role=seller`. Neither side can leak into the other's list.
The filters are server statuses rather than a local view: All sends no `status`;
Ongoing sends `pending`; Completed and Cancelled send their own values. The
design's separate **Pending** chip is **not shown**: the backend has a single
`pending` state, already labelled Ongoing across the app (`mobile/DESIGN.md`
§26), so the row carries the three real states plus All rather than two chips
that cannot return different records. Cards are labelled "Agreed price" and show
the exact `total_amount`; a listing's asking price is not in the resource and is
never shown here. Empty copy names the viewer's side ("No purchases yet" / "No
sales yet"). Tapping a card opens the existing detail screen with the persisted
id. Creation yields `pending`; the client never sends `status`.

The **Transaction Details** screen (`transaction_detail_screen.dart` +
`transaction_detail_content.dart`) is built only from a single
`GET /transactions/{id}` payload, and renders exactly what
`MobileTransactionResource` carries — nothing wider:

* **Amount.** The one money field is the server-derived `total_amount`,
  labelled "Transaction total". The resource has no `asking_price`, so no
  reference-vs-agreed pair is shown and none is fabricated; the screen states
  that the listing's reference asking price is not part of the transaction.
* **Counterparty** is `{ id, name, email }`, read through the server's `role`:
  the seller for a buyer, the buyer for a seller. The section title is "Seller"
  or "Buyer" accordingly and there is **no verification flag or location**, so
  no badge and no location row render. The action is "Message seller" or
  "Message buyer" and opens the existing `ChatScreen` with the counterparty's
  real id from the payload — the same chat route the marketplace uses.
* **Livestock** shows only Type and Breed, the only attributes the snapshot
  holds; age/weight/gender/health are not in the transaction record and an
  honest line says so.
* **Status** uses the real `pending`/`completed`/`cancelled` state with a
  next-step sentence that is true of the workflow; no completion affordance
  exists (OQ-15, backend 501).
* **Inquiry** is an honest statement, not a record: the resource links to no
  inquiry. The mobile API's only inquiry read surface is the seller's aggregate
  inbox, which has no transaction association or inquiry detail, and there is
  no buyer read endpoint (GAP-19). A buyer sees "Your inquiry"; a seller sees
  "Buyer inquiry".
* **Cancel** is pending-only, confirmed, and posted to
  `POST /transactions/{id}/cancel`; a `409` reloads the terminal state. The
  wording follows the role: "Cancel request" for a buyer, "Cancel sale" for a
  seller, including the confirmation dialog and immutable notice.

The **Transaction Status** screen (`transaction_status_screen.dart` +
`transaction_status_content.dart`, reached from the detail screen's "View
status") reuses the same single `GET /transactions/{id}` call through
`TransactionDetailController` — there is no separate status endpoint and none
is invented. It shows the listing summary (image when a real loadable URL
exists, title, server-derived total, status badge), a metadata card (request id
and the one persisted `created_at`, labelled "Request ID"/"Requested" for a
buyer and "Sale ID"/"Recorded" for a seller), a **Transaction Progress** tracker
whose wording follows the server's `role`, and a full-width **Message Seller**
or **Message Buyer** action that follows the same real chat route the detail
screen uses.

The tracker is derived from the real state machine, not the design's five-step
reference. The backend holds a **single current `status` and no transition
history**: `transactions` has no history table and no per-step timestamps
(migration `2026_09_20_120004_create_transactions_table`), and
`MobileTransactionResource` returns only `status`, `created_at` and
`updated_at`. Per the design (§5/§59), no per-step dates and no
seller-acceptance/delivery/receipt steps are fabricated. Instead
`TransactionTimeline.stepsFor` produces a truthful three-marker summary of the
actual workflow — Submitted, In progress, Outcome — where `pending` shows In
progress as current with an unknown outcome, `completed` shows the completion
as current, and `cancelled` shows a terminal, explicitly **not-completed**
outcome. The first marker is a purchase request for a buyer and a recorded sale
for a seller; `TransactionTimeline.stepsFor` takes the viewer's `TransactionRole`
so the words are true on both sides. A pale-green note states that only the
current status is recorded, so no dated history is shown. No payment, logistics
or transaction-confirmation step is implied; completion remains unavailable
(OQ-15).

**Still open below.** GAP-01 to GAP-09, GAP-11 to GAP-13 and GAP-16 are
`CLOSED` — implemented in the backend and consumed by the app. GAP-10, GAP-14,
GAP-15 and GAP-20 are `OPEN`. GAP-19 is `PARTIALLY CLOSED`: the seller inbox is
implemented and consumed, while buyer re-read, inquiry detail and seller
response remain missing.

Status: `CLOSED` = implemented and consumed. `PARTIALLY CLOSED` = some of the
surface exists and is consumed, with the rest still missing. `OPEN` = does not
exist. Nothing missing here has been worked around in the app.

| ID | Gap | Backend evidence | Blocks |
|---|---|---|---|
| GAP-01 | Mobile login for non-admin users | **CLOSED.** `POST /api/auth/login` (`routes/api.php`) with `Api/Auth/AuthController@login` and `MobileAuthService`. Administrators are refused with `403`. | — |
| GAP-02 | Registration endpoint | **CLOSED.** `POST /api/auth/register` with `Api/Auth/RegisterRequest`; the server fixes `role=user` and `seller_capability=buyer`. | — |
| GAP-03 | Current-user endpoint for non-admins | **CLOSED.** `GET /api/auth/me` returns a `UserResource` in the standard envelope. | — |
| GAP-04 | Logout for non-admins | **CLOSED.** `POST /api/auth/logout` revokes the calling mobile token. | — |
| GAP-05 | Marketplace browse (list/detail/filter/paginate) | **CLOSED.** `GET /api/listings` and `GET /api/listings/{listing}`, served by `Api/Marketplace/MarketplaceController` over `MobileListingResource` (seller narrowed to `id` + `name` by `MobileSellerResource`). `active`-only list; `404` for any non-visible listing. | — |
| GAP-06 | Listing photo delivery | **CLOSED.** [D-10]: `listings.photos` stores **bare filenames** (the model mutator normalises URLs, relative paths and filenames to the filename) and `MobileListingResource` serves **absolute URLs** via the `listing-photos` disk — local by default under `storage/app/public/listings` (requires `php artisan storage:link`), S3 by env (`LISTING_PHOTOS_DRIVER`). Sellers manage photos with `POST /api/seller/listings/{id}/photos` (multipart `photos[]`, jpeg/png/webp only, ≤5 MB each, ≤10 per listing including existing → `422`) and `DELETE /api/seller/listings/{id}/photos` (`photo` = the served URL or filename, unknown → `404`); owner-scoped (`404` for another seller), buyer → `403`, editable only while `draft`/`active` (`409`). The app's absolute-URL check now receives real URLs; the client never synthesises a base URL. | Listing management |
| GAP-07 | Seller verification submission | **CLOSED.** `POST /api/seller-verification` (`routes/api.php`) with `Api/SellerVerification/SellerVerificationController@store` and `SellerVerificationService`. Creates a `submitted` record; **grants no capability** — `seller_capability` is still written only by the admin approval endpoint. A second submission while one is `submitted`/`pending_review` is `409`; an approved seller is `403`; a rejected record may be resubmitted as a new row. `SubmitSellerVerificationRequest` allow-lists the four client fields and rejects server-owned ones with `422`. Deliberately **unthrottled** — see D-09. | — |
| GAP-08 | Own verification status retrieval | **CLOSED.** `GET /api/seller-verification/me` with `MobileSellerVerificationController@me`, returning the caller's latest record by `submitted_at DESC, id DESC` through `MobileSellerVerificationResource` (omits `seller`, `reviewer`, `user_id`, timestamps). `404` when the caller has never applied, which the app reads as "not submitted" rather than as an error. No route takes an id, so one buyer cannot read another's record. | — |
| GAP-09 | Seller listing CRUD, own listings only | **CLOSED.** Five routes in `routes/api.php` under `auth:sanctum` + `ability:mobile` + the `seller` capability gate, served by `Api/SellerListing/SellerListingController` → `SellerListingRequest`s → `SellerListingService` → `SellerListingRepository`, returned through `MobileListingResource`. `GET` lists the owner's own listings in all five statuses (`?status`, `?search`, paginated; scope always server-derived — a `seller_id` filter is `422`). `POST` creates a `draft`; a client-sent `status` or `seller_id` is `422`, never silently dropped. `POST /{id}/submit` moves `draft → pending` only, re-validating the stored listing (invalid → `422`, not queued); its body allow-list is empty, so *any* body field is `422`. `PATCH` edits `draft`/`active` only (D-24). `DELETE` removes `draft`/`inactive` only (D-12/D-25). Non-owner → `404`, buyer → `403`, and no seller path reaches `active` (D-02 rules 6–8). Tests: `backend/tests/Feature/SellerListing/MobileSellerListingTest.php`. | — |
| GAP-10 | AI price suggestion | `AiPriceEstimate` model and `ai_price_estimates` table exist. No controller, service, route or job. No pricing algorithm in the repository. `OPEN`. | AI price suggestion |
| GAP-11 | Transactions | **CLOSED** for the mobile surface. `GET /api/transactions` (own records only; `?role`, `?status`, paginated), `POST /api/transactions` (buyer creates `pending` from an `active` listing; body `listing_id` + `quantity` only; `total_amount` server-derived), `GET /api/transactions/{id}` (party-only; `404` otherwise) and `POST /api/transactions/{id}/cancel` (pending-only, either party; `409` once terminal), behind `auth:sanctum` + `ability:mobile`, served by `Api/Transaction/TransactionController` over `MobileTransactionResource`. `POST /{id}/complete` is **not implemented** and answers `501` (OQ-15), so the client offers no completion. Tests: `backend/tests/Feature/Transaction/MobileTransactionTest.php`. | Completion (OQ-15) |
| GAP-12 | Notifications | **CLOSED.** `GET /api/notifications` (paginated `notifications` list with `pagination` and `unread_count`), `GET /api/notifications/unread-count`, `PATCH /api/notifications/{id}/read`, `POST /api/notifications/read-all` and `DELETE /api/notifications/{id}`, all behind `auth:sanctum` + `ability:mobile` and served by `Api/Notification/NotificationController` over `NotificationResource`. Every route resolves the record from the token — no route takes a user id — and notification ids are UUID strings. The app consumes this through its own Notifications screen, reached from the Home bell and from the Messages screen's Notifications chip. | — |
| GAP-13 | Messaging | **CLOSED.** `GET /api/conversations`, `POST /api/conversations/{userId}/read`, `GET /api/conversations/{userId}/messages`, `POST /api/messages` and `PATCH /api/messages/{id}/read`, behind `auth:sanctum` + `ability:mobile`, served by `Api/Messaging/ConversationController` and `MessageController` over `ConversationResource` / `MessageResource`. Conversations are derived from message pairs (no table, no id); the caller's own participation scopes every query, and `sender_id`/`receiver_id` are server-derived on send. Consumed by the Messages inbox and chat screens. **No broadcasting** accompanies any of it — see GAP-20. No backend feature tests exist for these routes. | — |
| GAP-14 | Profile read/update for the current user | No endpoint. Admin can list users but not edit them. `OPEN`. | Profile |
| GAP-15 | Token lifetime policy | Mobile tokens are issued non-expiring, the same as admin tokens. No expiry, no refresh, no revocation-all. Still needs an explicit decision before shipping, so a mobile session currently lasts until it is logged out or revoked. | Security |
| GAP-16 | Sanctum token ability scoping for mobile | **CLOSED.** Mobile tokens carry `['mobile']`; mobile routes require `ability:mobile`. The `admin` group now also requires `ability:admin`, so a mobile token is refused by admin routes and an admin token is refused by mobile routes. Both directions are covered by `backend/tests/Feature/Auth/MobileAuthTest.php`. | — |
| GAP-19 | Buyer inquiry read; seller inquiry detail/response (mobile) | **PARTIALLY CLOSED.** `POST /api/inquiries` creates a buyer inquiry. `GET /api/seller/inquiries` lists the approved seller's own inbox through `SellerInquiryResource`, which omits `status` deliberately (open/responded/closed is an admin triage bookmark) and omits buyer email. `GET /api/inquiries`, `GET /api/inquiries/{inquiry}`, `PATCH /api/inquiries/{inquiry}/status` and `DELETE /api/inquiries/{inquiry}` remain admin-only (`routes/api.php`, `ability:admin`). There is still no buyer read endpoint, no inquiry detail for either side, and no seller response/status action. | Buyer inquiry list/detail, the Inquiry Sent screen's "View Inquiry" (rendered disabled with an honest caption), seller inquiry response/status, any server-driven status display |
| GAP-20 | Real-time messaging / notifications | **OPEN.** Nothing in the backend broadcasts messages or notifications: `BROADCAST_CONNECTION=log` in `backend/.env`/`.env.example`, no `config/broadcasting.php` or `config/reverb.php`, no `routes/channels.php`, no `app/Events/`, and `laravel/reverb` is not a dependency. The `reverb` service in `compose.yaml` is commented out. The app therefore has no WebSocket client (and no WS/echo package in `pubspec.yaml`), no event names to subscribe to, and no reconnect logic. Both inbox and thread recover by HTTP refresh instead. Building real-time requires broadcasting, authenticated private channels and named events on the server first. | Real-time message delivery, live badge/notification updates |

### Gaps that are design questions, not missing code

Report these; do not decide them unilaterally.

* **`livestock_type` categories.** The manuscript limits listings to
  **cattle, carabao, goat and swine** (functional documentation §4.1), but
  `listings.livestock_type` is still a plain `string` with no validation list,
  and the prototype also shows "Others" (open item MS-03). Where the list lives
  — backend validation exposed through an endpoint, or app constants — is
  still to be decided; do not hard-code a different list.
* **Currency and locale.** The Admin Web formats as `₱` / `en-PH`. The schema
  has no currency column. Assume PHP peso until told otherwise, and centralise
  the formatter so it is a one-line change.
* ~~No approved functional documentation exists~~ — **closed.** The
  functional documentation lives at
  `docs/AGROBENTA_FUNCTIONAL_DOCUMENTATION.md` and, since 2026-10-24, is
  aligned to the capstone manuscript, which is the final document (DG-01
  closed).

---

## Mobile API contract — **see `docs/MOBILE_API_CONTRACT_PROPOSAL.md`**

An abbreviated contract was drafted inline here during M0. It has since been
**superseded** by the full proposal at
`docs/MOBILE_API_CONTRACT_PROPOSAL.md`, which specifies every endpoint across all
ten required dimensions and carries the open-decision register. **Use that
document, not this section.** The inline copy is kept only as a record of what
M0 proposed.

**Business rules come from the capstone manuscript**, restated in
`docs/AGROBENTA_FUNCTIONAL_DOCUMENTATION.md`, which **outranks** the proposal
and this file. The earlier decision round (D-02 listing publication, D-03 price
suggestion, D-15 transaction status, and the security requirements) is kept
there only where the manuscript agrees. Where the proposal still reflects the
older rules, the functional documentation wins.

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

> **Updated 2026-10-24 — manuscript alignment.** Read these rows together with
> the functional documentation, which now settles several of them:
>
> * **GAP-10** — the estimation method is an **external AI API called by the
>   backend** (functional documentation §5.3). The provider is still open
>   (MS-09), so the rule below — never show a computed value before the service
>   exists — still applies. Buyers may see the suggestion as a reference (§5.1).
> * **GAP-11** — the completing actor is decided: **the seller accepts, then
>   the buyer confirms receipt** (§6.4). How the intermediate "seller accepted"
>   and "in delivery" steps are stored is still open (MS-12), so completion
>   stays blocked in the app until the backend implements it.
> * **GAP-17** — closed: admin `approve` / `reject` / `deactivate` exist.
> * **GAP-18** — still holds while admin approval is required. Whether a seller
>   may publish directly is open (MS-01).
> * Inquiries (seller view and response), document upload for verification and
>   the Account Mode switch are now in scope (§8.2, §3.3, §2.7).

Listing publication (D-02) and transaction status (D-15) were **decided** in
the earlier round. The register entries changed accordingly:

| Gap | Change |
|---|---|
| **GAP-06** photos | **Decided [D-10]**: no schema change is permitted to expose photos — the JSON column holds bare filenames, and the API serves absolute URLs. Upload/delete live under `/seller/listings/{id}/photos`. |
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
