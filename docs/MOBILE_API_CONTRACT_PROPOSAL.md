# Mobile API Contract — Proposal

**Status: PROPOSAL — NOT APPROVED, NOT IMPLEMENTED**
**Business rules: FINALIZED** (D-02, D-03, D-15 and the security requirements are
approved and locked in `AGROBENTA_FUNCTIONAL_DOCUMENTATION.md`)

Nothing in this document may be implemented, in `backend/` or in `mobile/`, until
it is approved. See `docs/AGENTS.md`.

**Authority order:** the approved rules in
`AGROBENTA_FUNCTIONAL_DOCUMENTATION.md` outrank this document. Where this
proposal conflicts with the functional documentation, the functional
documentation wins and this proposal is wrong.

### Decision round incorporated

The following business decisions are now **approved and authoritative**. This
proposal has been updated to match them, and the affected endpoints are no
longer blocked on those questions:

| Decision | Effect on this contract |
|---|---|
| **D-02** listing publication | `§5.4` rewritten. Seller can no longer send `status`; a `submit` action replaces it. Two new admin moderation endpoints are required. |
| **D-03** price suggestion | `§5.5` changed from "not implementable" to "interface specified, estimator blocked". |
| **D-15** transaction status | `§5.6` split: `cancel` is now fully specified; `complete` remains blocked. |
| **SEC** security requirements | New `§4.5` (authorization model), `§6.2` (allow-lists), and `§8.1` (resource separation) are now binding requirements, not recommendations. |

Endpoint contracts previously marked **blocked** on D-02, D-03 or D-15 have been
revised. Remaining blockers are listed in `§9`.

---

## 1. How to review this

The contract is specified per endpoint across ten dimensions:

| # | Dimension |
|---|---|
| 1 | Endpoint |
| 2 | Method |
| 3 | Authentication |
| 4 | Sanctum ability |
| 5 | Request fields |
| 6 | Validation |
| 7 | Response |
| 8 | Errors |
| 9 | Authorization |
| 10 | Ownership / resource scoping |

Review in this order:

1. **§4 Authorization model** and **§6 Security requirements** — the
   load-bearing decisions. Everything else depends on them, and the security
   requirements are now **binding** rather than advisory.
2. **§9 Remaining open decisions** — items that must be answered before the
   affected endpoints can be built. Several are genuine business-rule gaps, not
   oversights here.
3. **§5 Endpoint contracts** — endpoint by endpoint.
4. **§7 Findings** — places where the current Laravel implementation contradicts
   the approved rules or leaks data.
5. **§8 Resource shapes** — proposed wire format.

D-02, D-03, D-15 and the security requirements are **no longer open questions**.
Review those against the functional documentation, not against this document.

Every claim about the current implementation was verified against the source
files cited inline.

---

## 2. Scope boundary

### 2.1 What the mobile app may do

Marketplace browsing, seller verification submission and status, own-listing
management, AI price suggestion, own transactions, own notifications, own
messages, own profile.

### 2.2 What the mobile app must never do

Admin review of seller verification, user administration, settings, reports,
system activity, dashboards, and any cross-user data access.

It must also never call **listing moderation** endpoints. **[D-02] rule 8**
requires admin approval before a listing becomes `active` (§5.4b), and those
`approve` / `reject` / `deactivate` routes are **admin surface**. A mobile client
that can reach them defeats rule 6 — a seller cannot directly set a listing to
`active`, and must not be able to route around that by calling the admin
equivalent.

There is **no admin mobile application** (functional documentation §9.1). The
Admin Web is the only administrator surface.

### 2.3 Existing admin surface, for reference only

The following exist today and are **out of mobile scope**. Listed so the
boundary is explicit, and so the separation can be verified:

```
POST   /api/admin/auth/login          throttle:10,1
GET    /api/user                      auth:sanctum            ← see F-06
POST   /api/admin/auth/logout         auth:sanctum + admin
GET    /api/admin/auth/me             auth:sanctum + admin
GET    /api/admin/dashboard           auth:sanctum + admin
GET    /api/admin/users               auth:sanctum + admin
GET    /api/admin/listings            auth:sanctum + admin
GET    /api/admin/seller-verifications              auth:sanctum + admin
GET    /api/admin/seller-verifications/{id}          auth:sanctum + admin
POST   /api/admin/seller-verifications/{id}/approve auth:sanctum + admin
POST   /api/admin/seller-verifications/{id}/reject  auth:sanctum + admin
GET    /api/admin/transactions        auth:sanctum + admin
GET    /api/admin/activities          auth:sanctum + admin
GET    /api/admin/reports             auth:sanctum + admin
GET    /api/admin/settings            auth:sanctum + admin
PUT    /api/admin/settings            auth:sanctum + admin
```

`admin` is `EnsureUserIsAdmin` (`backend/bootstrap/app.php:18`), aliased in
`backend/app/Http/Middleware/EnsureUserIsAdmin.php`. **It checks
`$user->isAdmin()` — the `role` column — and never checks the Sanctum `admin`
ability.** See F-01.

---

## 3. Global conventions

Reuse the conventions the Admin Web already depends on. Do not introduce a
second envelope, a second error format, or a second pagination shape: the
existing frontend parses these and must not break.

### 3.1 Success envelope

Hand-rolled at the controller level, matching
`backend/app/Http/Controllers/Api/Admin/ListingController.php:30`:

```json
{ "success": true, "data": { } }
```

With a message (`.../Admin/AuthController.php:33`):

```json
{ "success": true, "message": "Logged in successfully.", "data": { } }
```

A `JsonResource` nested inside `data` **resolves flat** — it is not double
wrapped. The mobile client reads `data.<field>` directly.

### 3.2 Paginated envelope

Exactly the shape produced by
`.../Admin/ListingController.php:30-41` — reuse it verbatim:

```json
{
  "success": true,
  "data": {
    "listings": [ /* ListingResource[] */ ],
    "pagination": { "current_page": 1, "last_page": 4, "per_page": 15, "total": 55 }
  }
}
```

Four pagination keys only. No `links`, no `next_page_url`.

### 3.3 Error envelope

Laravel's default JSON errors. `shouldRenderJsonWhen` already forces JSON for
`api/*` (`backend/bootstrap/app.php:23`).

| Status | Body | Source |
|---|---|---|
| 401 | `{ "message": "Unauthenticated." }` | Sanctum |
| 403 | `{ "message": "..." }` | `abort(403, ...)` |
| 404 | `{ "message": "..." }` | route model binding |
| 409 | `{ "message": "..." }` | proposed, for state conflicts |
| 422 | `{ "message": "...", "errors": { "field": ["..."] } }` | validation |
| 429 | `{ "message": "Too Many Attempts." }` | throttle |
| 500 | `{ "message": "Server Error" }` | Laravel |

**Mobile must treat a non-2xx as failure regardless of body shape.** Note that
error bodies have **no `success` field** while success bodies do — see F-05.

Never surface a raw `message` from a 500 to a user.

### 3.4 Dates, money, enums

* **Dates** — ISO-8601 UTC strings, matching `?->toISOString()` in the existing
  resources.
* **Money** — `asking_price` and `total_amount` are `decimal(14,2)` and must
  serialise as **strings** with two decimals (`"12500.00"`), never floats.
  Clients must not do float arithmetic on money. Add explicit `decimal:2` casts
  where absent — see F-07.
  * **Amounts are as entered.** There is no currency column and none is to be
    added (functional documentation §11). The client formats for display; the
    server stores no currency.
* **Enums** — wire values are the bare strings: `role`, `seller_capability`,
  verification `status`, listing `status`, transaction `status`. Resources use
  `?->value`, so the client must treat a missing/null enum defensively.

### 3.5 Throttling

Login: `throttle:10,1`, matching `routes/api.php:20`. Register and
price-suggestion need their own limits — proposed `throttle:5,1` and
`throttle:30,1`. See D-09.

---

## 4. Authorization model — the load-bearing decision

### 4.1 Two separate contexts

Per functional documentation §9.3, admin and mobile are **separate
authorisation contexts** and must be separately enforced, in both directions.

A **Sanctum token ability** is the mechanism. The current admin token is
created with the `admin` ability (`backend/app/Services/AuthService.php:34`),
but that ability is never verified by any middleware — F-01.

The proposal requires the ability to actually gate access:

| Context | Token name | Ability | Middleware |
|---|---|---|---|
| Admin Web | `admin_token` | `['admin']` | `auth:sanctum` + `ability:admin` |
| Mobile | `mobile` | `['mobile']` | `auth:sanctum` + `ability:mobile` |

`abilities` and `ability` are Sanctum's default route aliases, so no custom
middleware is needed — **verify this on the installed Sanctum version before
planning the work.**

### 4.2 What a mobile token authorises

A `mobile` token authorises **only** the endpoints in §5, and only for the
account it was issued to. It confers **no** admin authority, regardless of the
`role` column. If the underlying account is an administrator, the token is
still mobile-scoped.

### 4.3 Role versus seller capability

These are independent (functional documentation §2.4) and the contract must
never conflate them:

* `role` — `user` | `admin`. **Not used for any mobile feature gate.**
* `seller_capability` — `buyer` | `seller`. **The only** gate on selling
  actions.

An approved seller is `role=user` **and** `seller_capability=seller`. Selling
rights derive from `seller_capability` alone.

`User::isApprovedSeller()` (`backend/app/Models/User.php:50`) already
implements exactly this and should be the single check used. `isAdminSeller()`
(line 48) is for admin tooling and is **not** a mobile gate.

### 4.4 Client-visible authority

`UserResource` already returns `role` and `seller_capability`, which is
sufficient for the client to render "Become a Seller". The client may use these
**only** to decide what to show. Every gate in §4.3 is re-evaluated server-side
on every request.

### 4.5 Security requirements — BINDING **[SEC]**

These are approved requirements (functional documentation §10), not
recommendations. They are a **precondition** for implementing any mobile write
endpoint. Full detail lives in the functional documentation; the contract-level
consequences are below.

#### 4.5.1 Fields that must never come from a mobile request

| Field | Derived from | Contract consequence |
|---|---|---|
| `users.role` | internal assignment only | Never a request field on **any** endpoint |
| `users.seller_capability` | the approved verification workflow | Never a request field; not on `PATCH /profile` |
| `listings.seller_id` | `$me` | Never a request field on create or update |
| `transactions.buyer_id` | `$me` | Never a request field |
| `transactions.seller_id` | `listing.seller_id` | Never a request field |
| `messages.sender_id` | `$me` | Never a request field |

A client must not be able to send `{"seller_capability": "seller"}` and become a
seller, nor name another user in `seller_id` or `buyer_id`. **Seller capability
is granted only through the approved verification workflow** — there is no other
path to it.

#### 4.5.2 Explicit allow-lists

Every write endpoint below uses a dedicated Form Request permitting **only** the
documented client-settable fields. A denylist is not acceptable: it fails open
when a field is added later. Adding a field to a model must never make it
client-settable.

#### 4.5.3 Authentication separation

Mobile authentication is separate from Admin Web authorization. The admin login
flow is **not reused**, and no mobile user receives an admin-authority token.
See `§5.1.2` and functional documentation §10.5.

---

## 5. Endpoint contracts

All paths are relative to `/api`. Unless stated, responses are `200` and use
§3.1. The authenticated user is `$me`; the token is the `mobile`-ability
Sanctum token from §4.1.

### 5.1 Authentication

---

#### `POST /auth/register`

| Dimension | Specification |
|---|---|
| **Endpoint** | `/api/auth/register` |
| **Method** | `POST` |
| **Authentication** | None — public |
| **Ability** | N/A |
| **Request fields** | `name` (string, required)<br>`email` (string, required)<br>`password` (string, required)<br>`password_confirmation` (string, required)<br>`device_name` (string, optional, default `mobile`) |
| **Validation** | `name` → `required`, `string`, `max:255`<br>`email` → `required`, `string`, `email`, `max:255`, `unique:users,email`<br>`password` → `required`, `string`, `min:8`, `confirmed`<br>`device_name` → `sometimes`, `string`, `max:255` |
| **Response** | `201`, §3.1 with message. `data` = `{ token, token_type: "Bearer", user: UserResource }` — identical to login §5.1.2 |
| **Errors** | `422` validation<br>`409` email already registered (defence in depth behind `unique`)<br>`429` throttle |
| **Authorization** | None. Public self-registration. |
| **Ownership** | Server creates the user. |

**New accounts are always `role=user`, `seller_capability=buyer`**
(functional documentation §2.1). This matches the migration defaults but
**must be set explicitly**, because `role` and `seller_capability` are both in
`#[Fillable]` on the model (`User.php:17`) and a mass-assignment guard is
**mandatory** under [SEC] §4.5.2 — a request that omits them must not be able to
supply them.

**Open:** whether registration returns a token or requires a subsequent login
(D-01). Whether registration is open at all, or invite-only (D-22).

---

#### `POST /auth/login`

| Dimension | Specification |
|---|---|
| **Endpoint** | `/api/auth/login` |
| **Method** | `POST` |
| **Authentication** | None — public |
| **Ability** | N/A |
| **Request fields** | `email` (string, required)<br>`password` (string, required)<br>`device_name` (string, optional, default `mobile`) |
| **Validation** | Identical to the existing `Auth\LoginRequest` (`backend/app/Http/Requests/Auth/LoginRequest.php:25`): `email` → `required`,`string`,`email`; `password` → `required`,`string`. Prefer **reusing that request class** so the two logins cannot drift. |
| **Response** | `200`, §3.1 with message. `data` = `{ token, token_type: "Bearer", user: UserResource }` — byte-compatible with the admin login response at `.../Admin/AuthController.php:33` |
| **Errors** | `401` invalid credentials — **one generic message, never distinguishing "no such user" from "wrong password"**<br>`403` account not permitted to use mobile (D-03)<br>`429` `throttle:10,1` |
| **Authorization** | `role=user` only. The admin check in `AuthService::login()` (line 28) must be **inverted for this path** — mobile admits non-admins and rejects admins. |
| **Ownership** | Server-issued. |

**This is a new service method, not a reuse of `AuthService::login()`.** That
method hard-requires `isAdmin()` and issues an `admin` ability. Reusing it would
give every mobile user a token carrying admin authority. **F-02.**

**[SEC] §10.5 — this is now a binding requirement, not a recommendation:**

* Mobile authentication is **separate** from Admin Web authorization.
* The admin login flow is **not reused**.
* **No mobile user receives an admin-authority token.**
* Mobile users receive a token scoped to **regular user / mobile** access.

The token is `createToken('mobile', ['mobile'])`. The client stores it via the
existing `TokenStorage` in `mobile/lib/core/storage/`.

**Still open:** whether a `role = admin` account may authenticate through this
flow at all, and if so which authorisation context it carries. [SEC] settles
that such a token is never admin-authority; it does not settle whether the
account may hold one (D-03b, functional documentation OQ-12).

---

#### `GET /auth/me`

| Dimension | Specification |
|---|---|
| **Endpoint** | `/api/auth/me` |
| **Method** | `GET` |
| **Authentication** | Required |
| **Ability** | `mobile` |
| **Request fields** | None |
| **Validation** | N/A |
| **Response** | `200`, §3.1. `data` = `UserResource` — matches `.../Admin/AuthController.php:60` |
| **Errors** | `401` missing/expired/revoked token<br>`403` token lacks the `mobile` ability |
| **Authorization** | Any valid `mobile` token. |
| **Ownership** | Returns **only** `$me`. No id parameter, no cross-user read. |

`UserResource` returns `id, name, email, role, seller_capability,
email_verified_at, created_at, updated_at`.

**Note F-04:** `email_verified_at` can never be non-null — `MustVerifyEmail` is
commented out at `User.php:5` and nothing sets the column. The field is
currently dead. Either implement verification or drop it from the mobile
contract; do not ship a permanently-null "verified" flag.

This endpoint **supersedes `GET /api/user`** for mobile. `GET /api/user`
(F-06) should be removed or admin-gated.

---

#### `POST /auth/logout`

| Dimension | Specification |
|---|---|
| **Endpoint** | `/api/auth/logout` |
| **Method** | `POST` |
| **Authentication** | Required |
| **Ability** | `mobile` |
| **Request fields** | None |
| **Validation** | N/A |
| **Response** | `200`, §3.1 with `message: "Logged out successfully."`, **no `data`** — matches `.../Admin/AuthController.php:47` |
| **Errors** | `401`, `403` |
| **Authorization** | Any valid `mobile` token. |
| **Ownership** | Revokes **only the calling token**: `$user->currentAccessToken()->delete()` (`AuthService.php:43`). Never another user's token, never by id from the request. |

**Open:** current-token-only (proposed, matches existing) or revoke-all-devices
(D-04).

---

### 5.2 Marketplace

---

#### `GET /listings`

| Dimension | Specification |
|---|---|
| **Endpoint** | `/api/listings` |
| **Method** | `GET` |
| **Authentication** | Required — `auth:sanctum` + `ability:mobile` |
| **Ability** | `mobile` |
| **Request fields** | `search` (string, optional)<br>`livestock_type` (string, optional)<br>`location` (string, optional)<br>`min_price` (decimal, optional)<br>`max_price` (decimal, optional)<br>`page` (int, optional, default 1)<br>`per_page` (int, optional, default 15, max 50) |
| **Validation** | `search` `sometimes`,`string`,`max:255`<br>`livestock_type` `sometimes`,`string`,`max:255` — free text, **not** an enum (functional documentation §4.1)<br>`min_price`/`max_price` `sometimes`,`numeric`,`min:0`<br>`page` `sometimes`,`integer`,`min:1`<br>`per_page` `sometimes`,`integer`,`between:1,50` |
| **Response** | `200`, §3.2. `data.listings` = `ListingResource[]`, `data.pagination` = 4 keys |
| **Errors** | `401`, `403`, `422` |
| **Authorization** | Any authenticated user. **`status` is not an accepted filter.** Per **[D-02] rule 9, buyers browse only `active` listings**, so the result set is hard-restricted server-side to `status = active`. `draft`, `pending`, `sold` and `inactive` never appear. |
| **Ownership** | N/A — a marketplace view. |

**Visibility matrix — [D-02] rules 1, 2, 3, 5, 9:**

| Status | Buyer marketplace | Owner | Admin |
|---|---|---|---|
| `draft` | invisible | sees | sees |
| `pending` | invisible | sees | sees |
| `active` | **visible** | sees | sees |
| `sold` | not listed | sees | sees |
| `inactive` | invisible | sees | sees |

This is a **server-side query restriction**, not a client-side filter. A
`status` query parameter must be rejected, not honoured.

`seller.email` must **not** be returned here — see F-08 and the binding
resource-separation requirement in §8.1. A marketplace listing response needs a
public seller projection, not `ListingResource`.

**Open:** whether signed-out visitors may browse (D-05). Whether a `sold`
listing stays directly viewable by URL, outside the list — not stated by D-02
(D-23).

---

#### `GET /listings/{listing}`

| Dimension | Specification |
|---|---|
| **Endpoint** | `/api/listings/{listing}` |
| **Method** | `GET` |
| **Authentication** | Required — `auth:sanctum` + `ability:mobile` |
| **Ability** | `mobile` |
| **Request fields** | `listing` (route model binding) |
| **Validation** | Integer, must exist |
| **Response** | `200`, §3.1. `data` = listing detail, per §8.2 |
| **Errors** | `401`, `403`, `404` |
| **Authorization** | `active` → any authenticated user.<br>Every other status → **owner only**; a non-owner receives `404`, not `403`, so listing existence is not disclosed. |
| **Ownership** | Owner check is `listing.seller_id === $me->id`. Never trusted from the request. |

Per [D-02], `draft` is private to the seller and `inactive` is not publicly
available, so both are owner-only. `pending` is likewise not visible in the
buyer marketplace.

`sold` is not listed in the marketplace ([D-02] rule 9) and is no longer
available for new transactions (rule 4). Whether a `sold` listing remains
directly viewable by URL is not stated by D-02 — **D-23**. Until answered, treat
`sold` as owner-only here rather than assuming it stays public.

---

### 5.3 Seller verification

---

#### `POST /seller-verification`

| Dimension | Specification |
|---|---|
| **Endpoint** | `/api/seller-verification` |
| **Method** | `POST` |
| **Authentication** | Required |
| **Ability** | `mobile` |
| **Request fields** | `business_name` (string, **required**)<br>`business_location` (string, optional)<br>`business_description` (string, optional)<br>`id_document_ref` (string, optional) |
| **Validation** | `business_name` `required`,`string`,`max:255`<br>`business_location` `sometimes`,`string`,`max:255`<br>`business_description` `sometimes`,`string`,`max:2000`<br>`id_document_ref` `sometimes`,`string`,`max:255` — **a reference only, never an uploaded document** (functional documentation §3.3) |
| **Response** | `201`, §3.1. `data` = `SellerVerificationResource` with `status: "submitted"` and `submitted_at` set |
| **Errors** | `401`, `403`<br>`409` an open verification already exists (D-06)<br>`422` |
| **Authorization** | Any authenticated user. Rejected if `seller_capability = seller` — an approved seller has nothing to submit (D-07). |
| **Ownership** | `user_id` = `$me->id`, server-set. |

**This endpoint is where the resubmission rule becomes code.** Per functional
documentation §3.2:

* Submitting creates a **new row**. It never updates an existing record back to
  `submitted`.
* Submission is permitted **only** when the most recent record is `rejected`.
  If the most recent record is `submitted` or `pending_review`, reject with
  `409` — `SellerVerificationStatus::isOpen()` already exists and is the check.
* "Most recent" must be resolved by `submitted_at desc, id desc` — deterministic,
  and not dependent on insertion-time ties.
* `seller_capability` stays `buyer`. Submission alone grants nothing.

**Reinforced by the decision round:** *"A user cannot become a seller merely by
modifying their own account fields. Seller capability must be granted only
through the approved verification workflow."* This endpoint — plus the admin
review endpoints — is the **only** way `seller_capability` becomes `seller`.
Combined with [SEC] §4.5.1, that means `seller_capability` is not writable from
any mobile endpoint at all.

No such guard exists anywhere today, because no submission endpoint exists.
F-09.

`SellerVerificationResource` embeds `seller.email` and a `reviewer` object —
**strip both for the mobile response** (F-08). The resource was written for
administrators.

---

#### `GET /seller-verification/me`

| Dimension | Specification |
|---|---|
| **Endpoint** | `/api/seller-verification/me` |
| **Method** | `GET` |
| **Authentication** | Required |
| **Ability** | `mobile` |
| **Request fields** | None |
| **Validation** | N/A |
| **Response** | `200`, §3.1. `data` = the **most recent** `SellerVerificationResource`, mobile-shaped, including `admin_note` so a rejected user can see why |
| **Errors** | `401`, `403`, `404` never submitted |
| **Authorization** | `$me` only. |
| **Ownership** | Filtered by `user_id = $me->id`. |

Because history is preserved (§3.2), **this endpoint must return exactly one
record — the latest — not an array.** A client rendering "your verification
status" must not have to pick the newest of N.

Should it also expose full history? A read-only
`GET /seller-verification/history` is proposed for transparency. **Open
(D-08).**

---

### 5.4 Own listings (approved sellers)

All four require `seller_capability = seller` — `User::isApprovedSeller()`.
A buyer receives `403`.

---

#### `GET /seller/listings`

| Dimension | Specification |
|---|---|
| **Endpoint** | `/api/seller/listings` |
| **Method** | `GET` |
| **Authentication** | Required |
| **Ability** | `mobile` |
| **Request fields** | `status` (string, optional — **all** statuses permitted here)<br>`search` (string, optional)<br>`page`, `per_page` (as §5.2) |
| **Validation** | `status` `sometimes`,`string`,`Rule::in(['draft','pending','active','sold','inactive'])` |
| **Response** | `200`, §3.2 |
| **Errors** | `401`, `403`, `422` |
| **Authorization** | `seller_capability = seller` |
| **Ownership** | `seller_id = $me->id` **always injected server-side.** A `seller_id` filter must be rejected, not honoured. |

Unlike §5.2, a seller sees **all** their own statuses including `draft` and
`pending`.

---

#### `POST /seller/listings`

| Dimension | Specification |
|---|---|
| **Endpoint** | `/api/seller/listings` |
| **Method** | `POST` |
| **Authentication** | Required |
| **Ability** | `mobile` |
| **Request fields** | `livestock_type` **required**<br>`location` **required**<br>`asking_price` **required**<br>`quantity` **required**<br>`breed`, `age_value`, `age_unit`, `gender`, `weight_value`, `weight_unit`, `health_status`, `vaccination`, `short_description`, `additional_notes` (all optional)<br>`photos` optional array, default `[]`<br>**`status` is NOT accepted.** |
| **Validation** | `livestock_type` `required`,`string`,`max:255` — free text, no enum (functional doc §4.1)<br>`location` `required`,`string`,`max:255`<br>`asking_price` `required`,`numeric`,`min:0`,`max:99999999999.99`<br>`quantity` `required`,`integer`,`min:1`<br>`age_value` `sometimes`,`integer`,`min:0`<br>`age_unit` `sometimes`,`Rule::in(['day','month','year'])`<br>`gender` `sometimes`,`Rule::in(['male','female'])`<br>`weight_value` `sometimes`,`numeric`,`min:0`<br>`weight_unit` `sometimes`,`Rule::in(['kg','lb'])`<br>`age_value`↔`age_unit` and `weight_value`↔`weight_unit` must be supplied together — `required_with`<br>`photos` `sometimes`,`array`<br>`photos.*` `string`<br>**`status` and `seller_id` must be rejected if present** — [SEC] §4.5 |
| **Response** | `201`, §3.1. `data` = listing, `status` is `draft` |
| **Errors** | `401`, `403` not an approved seller, `422` |
| **Authorization** | `seller_capability = seller` |
| **Ownership** | `seller_id = $me->id`, server-set. `Listing` is `#[Fillable]` — `seller_id` **must** be excluded by allow-list ([SEC] §4.5.2). F-11. |

**`asking_price` is the seller's own decision** (functional doc §4.3, §5.2). No
default, no server-side pricing. An AI suggestion (§5.5) may inform it but must
never write it — **[D-03] rule 4**.

**`status` is not a request field. [D-02] rules 6 and 7.** The server sets
`draft` on create. A seller **cannot** set `active`, and the only status a
seller can cause is `pending`, via the submit action below. A request carrying
`status` must be **rejected**, not silently ignored — silently dropping it hides
a client bug, and accepting it is rule 6 violated.

**`photos` is a JSON column, not an upload (F-13).** Per **[SEC] / functional
doc §4.5**, the mobile API must expose photos, and **the schema must not change
to make that possible**. The representation is decided at implementation time —
**D-10**.

---

#### `POST /seller/listings/{listing}/submit`

| Dimension | Specification |
|---|---|
| **Endpoint** | `/api/seller/listings/{listing}/submit` |
| **Method** | `POST` |
| **Authentication** | Required |
| **Ability** | `mobile` |
| **Request fields** | None. The listing's own fields are the submission content. |
| **Validation** | N/A — the listing must satisfy the §5.4 create rules. **[D-02] rule 7: submission moves a *valid* draft to `pending`.** An invalid listing is rejected with `422`, not queued. |
| **Response** | `200`, §3.1, listing with `status: "pending"` |
| **Errors** | `401`, `403`, `404` not yours<br>`409` not currently `draft` — already `pending`, `active`, `sold` or `inactive` |
| **Authorization** | `seller_capability = seller` |
| **Ownership** | `listing.seller_id === $me->id`, else `404` |

**This endpoint is the only way a seller changes a listing's status. [D-02]
rule 7.** It performs exactly one transition: `draft → pending`.

There is deliberately **no** `?status=` variant, no "publish" alias, and no
seller-callable route that reaches `active` — that is [D-02] rule 6, and
admin approval is rule 8.

**Not settled by D-02:** once a listing is `pending` it cannot return to
`draft`, and a rejection sends it to `inactive` with no path back
(functional doc A-01, A-02, OQ-16). A seller whose listing is rejected therefore
has no route to revise and resubmit the same record. Recorded, not invented.

---

#### `PATCH /seller/listings/{listing}`

| Dimension | Specification |
|---|---|
| **Endpoint** | `/api/seller/listings/{listing}` |
| **Method** | `PATCH` |
| **Authentication** | Required |
| **Ability** | `mobile` |
| **Request fields** | Any subset of the §5.4 create fields, **excluding `status`**. Absent keys are unchanged. |
| **Validation** | As §5.4, but every field `sometimes`. Pairs still validated together. `status` and `seller_id` rejected if present. |
| **Response** | `200`, §3.1, updated listing |
| **Errors** | `401`, `403`, `404` not yours, `409` not editable in its current status, `422` |
| **Authorization** | `seller_capability = seller` |
| **Ownership** | **`listing.seller_id === $me->id`, else `404`.** A partial-update endpoint is a classic IDOR target; the ownership check is mandatory and must not be a `authorize`-after-fetch afterthought. |

`seller_id` is not updatable, and `status` is not settable here — **[D-02] rule
6**. Publication goes through `submit` (§5.4).

**Editable statuses:** `draft` and `active` are clearly editable. **[D-02] does
not address editing a `pending` listing while it awaits review, nor a `sold` or
`inactive` one** — recorded as **D-24** rather than guessed. Until answered,
restrict updates to `draft` and `active`.

---

#### `DELETE /seller/listings/{listing}`

| Dimension | Specification |
|---|---|
| **Endpoint** | `/api/seller/listings/{listing}` |
| **Method** | `DELETE` |
| **Authentication** | Required |
| **Ability** | `mobile` |
| **Request fields** | None |
| **Validation** | N/A |
| **Response** | `200`, §3.1 with `message: "Listing deleted successfully."`, no `data` |
| **Errors** | `401`, `403`, `404`<br>`409` referenced by a transaction (D-12) |
| **Authorization** | `seller_capability = seller` |
| **Ownership** | `listing.seller_id === $me->id`, else `404` |

**Prefer a soft delete.** A `sold` listing is part of a completed transaction
record; hard-deleting it breaks referential and audit history. No `deleted_at`
column exists — **D-12**.

**[D-02] interaction — deletion must not become self-deactivation.** The
transition `active → inactive` is reserved to **admin** ([D-02] transition
table). A seller who can `DELETE` an `active` listing has self-deactivated it
and bypassed that rule. Restrict deletion to `draft` and `inactive` until the
interaction is settled — recorded as **D-25**, not invented.

---

### 5.4b Required admin listing moderation — NOT mobile scope

**[D-02] rule 8 makes administrator approval a precondition for `active`,** so
the Admin Web needs endpoints that **do not exist today**. `routes/api.php:27`
exposes `GET /api/admin/listings` and nothing else — admin can currently only
*read* listings. This is a required capability with no implementation
(functional doc OQ-14, F-10).

Specified here because D-02 makes it mandatory, but it is **admin surface, not
mobile surface**. The mobile app must never call it.

```
POST /api/admin/listings/{listing}/approve     auth:sanctum + admin
POST /api/admin/listings/{listing}/reject      auth:sanctum + admin
POST /api/admin/listings/{listing}/deactivate  auth:sanctum + admin
```

| Transition | Endpoint | Guard |
|---|---|---|
| `pending → active` | `approve` | must be `pending` |
| `pending → inactive` | `reject` | must be `pending`; takes an `admin_note` |
| `active → inactive` | `deactivate` | must be `active` |

Each must validate the current status server-side and return `409` on an illegal
transition, so a double-approve or a late rejection cannot silently corrupt the
lifecycle. These use the admin `admin`-ability context (§4.1), **not** the
mobile one.

**No reactivation endpoint is specified**, because [D-02] defines no path back
to `active` from `inactive` (functional doc A-02 / OQ-16). Do not add one.

---

### 5.5 AI price suggestion

---

#### `POST /seller/listings/{listing}/price-suggestion`

| Dimension | Specification |
|---|---|
| **Endpoint** | `/api/seller/listings/{listing}/price-suggestion` |
| **Method** | `POST` |
| **Authentication** | Required |
| **Ability** | `mobile` |
| **Request fields** | None — the listing already carries every input the estimate needs |
| **Validation** | N/A |
| **Response** | `200`, §3.1. `data` = `{ listing_id, estimated_min, estimated_max, estimated_value, basis, input_snapshot, estimated_at }` |
| **Errors** | `401`, `403`, `404` not yours, `422` insufficient comparable data, `429` |
| **Authorization** | `seller_capability = seller` |
| **Ownership** | `listing.seller_id === $me->id`, else `404` |

**The binding constraint — decision support only [D-03].** This endpoint:

* **MUST NOT** write, default, or overwrite `asking_price`. Rule 4:
  `listings.asking_price` remains the seller's final chosen price.
* **MUST NOT** accept a price and record agreement. No acceptance field exists
  and none is to be added.
* **MUST** return `basis`, a meaningful human-readable derivation. A range with
  no stated basis is not decision support.
* **MUST** be optional. A seller may publish without ever calling it.
* **MUST** be owner-only in this direction. Whether a buyer may *see* the range
  on a listing is **D-13**.

The output surface is exactly four values: estimated minimum, estimated maximum,
a suggested/reference value, and a basis/explanation **[D-03] rule 1**. Nothing
beyond those four is to be returned.

### 5.5.1 Implementation constraints **[D-03]**

* The estimation process **must be implemented as a dedicated service** (rule 5).
  Not inline controller logic, not a model method. The API layer calls a
  service; the service owns the estimation.
* **Do not claim that a machine-learning model exists** unless an actual model or
  integration has been implemented (rule 6). This binds code comments, commit
  messages and documentation. The approved feature name is "AI price
  suggestion"; the name is not evidence of a model.
* **Do not invent an AI algorithm** during the API implementation phase (rule 7).

### 5.5.2 What is now buildable, and what is not

**Settled by D-03** — the endpoint path, HTTP method, authentication, ability,
request, response shape, authorization, ownership, and persistence are all
specified above and may be built.

**Still blocked — the estimator's interior.** How `estimated_min`,
`estimated_max` and `estimated_value` are actually computed is **not decided**
(functional doc OQ-03). Until the method is explicitly documented:

* The service may exist with a documented, clearly-labelled **unavailable**
  path, or the endpoint may not be exposed at all.
* It **must never return a fabricated number.** A plausible-looking invented
  formula is explicitly prohibited by rule 7.

`ai_price_estimates` has a schema and nothing writes to it, and no algorithm,
model, or integration exists in the repository. That is unchanged by D-03, which
mandates *how* the estimator must be built without deciding *what* it computes.

**Structural note:** `ai_price_estimates.listing_id` is `NOT NULL` with a
foreign key, so a suggestion can only exist **after** a listing is created. The
flow is therefore *create draft → request suggestion → set `asking_price` →
submit for review* — which is why the price must be chosen before `submit`, and
why an `active` listing has no suggestion endpoint of its own.

---

### 5.6 Transactions

**[D-15] settles the lifecycle.** States are exactly `pending`, `completed`,
`cancelled`. Transitions are exactly `pending → completed` and
`pending → cancelled`. **Both `completed` and `cancelled` are terminal.**

```
  PENDING ──confirm──> COMPLETED   (terminal)
      │
      └──cancel──> CANCELLED       (terminal)
```

**`cancel` is fully specified below and is implementable. `complete` is not** —
[D-15] rule 4 requires "the appropriate transaction confirmation" without
naming the actor, and that ambiguity is documented rather than invented
(functional doc A-03 / OQ-15).

There is **no** payment, refund, shipping, delivery, or dispute state or
endpoint — [D-15] rules 8–10.

---

#### `GET /transactions`

| Dimension | Specification |
|---|---|
| **Endpoint** | `/api/transactions` |
| **Method** | `GET` |
| **Authentication** | Required |
| **Ability** | `mobile` |
| **Request fields** | `role` (string, optional: `buyer`\|`seller`)<br>`status` (string, optional)<br>`page`, `per_page` |
| **Validation** | `role` `sometimes`,`Rule::in(['buyer','seller'])`<br>`status` `sometimes`,`Rule::in(['pending','completed','cancelled'])` |
| **Response** | `200`, §3.2, mobile-shaped transactions |
| **Errors** | `401`, `403`, `422` |
| **Authorization** | Any authenticated user |
| **Ownership** | `buyer_id = $me->id` **or** `seller_id = $me->id`. One `OR` group, never a filter that lets the caller pick an arbitrary user. Both sides of a transaction are visible to the counterparty by design — but **only** the email address of the counterparty, never unrelated users. |

`TransactionResource` embeds `buyer.email` **and** `seller.email` — see F-08.
Restrict to the counterparty's fields.

---

#### `POST /transactions`

| Dimension | Specification |
|---|---|
| **Endpoint** | `/api/transactions` |
| **Method** | `POST` |
| **Authentication** | Required |
| **Ability** | `mobile` |
| **Request fields** | `listing_id` (int, required)<br>`quantity` (int, required) |
| **Validation** | `listing_id` `required`,`integer`,`exists:listings,id`<br>`quantity` `required`,`integer`,`min:1` |
| **Response** | `201`, §3.1, mobile-shaped transaction |
| **Errors** | `401`, `403` not an approved seller, `404` listing not found, `409` not `active`/own listing/insufficient quantity, `422` |
| **Authorization** | The caller is the **buyer** ([D-15] rule 1) |
| **Ownership** | **`seller_id = listing.seller_id` server-derived from the listing. `buyer_id = $me->id`. `total_amount = listing.asking_price × quantity`, computed server-side.** |

**Non-negotiable, per functional documentation §6 and [SEC] §4.5.1:**

* `buyer_id`, `seller_id` and `total_amount` are **never** accepted from the
  request. A client-supplied `buyer_id` is privilege escalation; a
  client-supplied `total_amount` is price tampering. All three must be rejected
  if present, not silently dropped — all are `#[Fillable]` on the model. F-11.
* A user cannot be both buyer and seller (§6.2) → `409`.
* The listing must be `active` — **[D-02] rule 3**, since only `active`
  listings are publicly available — and must have
  `quantity >= requested`.
* A `sold` listing accepts no new transaction ([D-02] rule 4).
* Initial status is `pending` ([D-15] rule 2).

**The buyer initiates; the seller does not create transactions** ([D-15]
rule 1). A seller has no create endpoint.

There is **no payment capture** (§6.3, [D-15] rule 8). A transaction records an
arrangement. No payment method, reference, or settlement field is to be added —
and none exists.

---

#### `GET /transactions/{transaction}`

| Dimension | Specification |
|---|---|
| **Endpoint** | `/api/transactions/{transaction}` |
| **Method** | `GET` |
| **Authentication** | Required |
| **Ability** | `mobile` |
| **Request fields** | `transaction` (route model binding) |
| **Validation** | Integer, must exist |
| **Response** | `200`, §3.1, mobile-shaped transaction |
| **Errors** | `401`, `403`, `404` |
| **Authorization** | Any authenticated user |
| **Ownership** | `buyer_id === $me->id` **or** `seller_id === $me->id`, **else `404`.** Never a `403` — that confirms the transaction exists. |

---

#### `POST /transactions/{transaction}/cancel` — IMPLEMENTABLE

| Dimension | Specification |
|---|---|
| **Endpoint** | `/api/transactions/{transaction}/cancel` |
| **Method** | `POST` |
| **Authentication** | Required |
| **Ability** | `mobile` |
| **Request fields** | None. Optionally an `admin_note`-style reason is **not** permitted — no such column exists. |
| **Validation** | N/A |
| **Response** | `200`, §3.1, updated transaction with `status: "cancelled"` |
| **Errors** | `401`, `403`, `404`<br>`409` already `completed` or `cancelled` — both terminal ([D-15] rules 6, 7) |
| **Authorization** | **Either party** — the buyer or the seller ([D-15] rule 5) |
| **Ownership** | `buyer_id === $me->id` **or** `seller_id === $me->id`, else `404` |

**[D-15] rule 5: pending transactions may be cancelled by the buyer or by the
seller, according to the API's defined cancellation operation.** This *is* that
operation — a single endpoint both parties may call, rather than separate
buyer/seller routes. Rule 5 delegates the operation definition to the contract,
so defining it here is in scope.

Guard the current status server-side: only `pending` may be cancelled. Never
transition out of a terminal state.

#### `POST /transactions/{transaction}/complete` — BLOCKED, do not implement

| Dimension | Specification |
|---|---|
| **Endpoint** | `/api/transactions/{transaction}/complete` |
| **Method** | `POST` |
| **Authentication** | Required |
| **Ability** | `mobile` |
| **Request fields** | None |
| **Validation** | N/A |
| **Response** | `200`, §3.1, updated transaction with `status: "completed"` |
| **Errors** | `401`, `403`, `404`, `409` not `pending` |
| **Authorization** | **UNRESOLVED — see below. Do not guess.** |
| **Ownership** | Counterparty of the transaction, else `404` |

> **[D-15] A-03 — the actor is not specified.** Rule 4 requires "the appropriate
> transaction confirmation" without saying who performs it or what it consists
> of. It is not stated whether completion is confirmed by the seller, by the
> buyer, or requires mutual agreement.
>
> **Implement `cancel`, `GET`/`POST` create, and detail now. Leave `complete`
> unimplemented** until functional doc OQ-15 is answered.
>
> The narrowness of this gap is worth noting: rules 8–10 remove payment,
> shipping and delivery from scope, so completion is a pure agreement step with
> no external event to observe. That is precisely why the actor must be stated
> rather than inferred — guessing "the seller confirms" would bake an unapproved
> business rule into the API.

---

### 5.7 Notifications

Requires two new resources — `NotificationResource` and a paginated
collection wrapper. Neither exists.

---

#### `GET /notifications`

| Dimension | Specification |
|---|---|
| **Endpoint** | `/api/notifications` |
| **Method** | `GET` |
| **Authentication** | Required |
| **Ability** | `mobile` |
| **Request fields** | `unread_only` (bool, optional)<br>`page`, `per_page` |
| **Validation** | `unread_only` `sometimes`,`boolean`<br>`per_page` `sometimes`,`integer`,`between:1,50` |
| **Response** | `200`, §3.2. `data.notifications` = notification objects per §8.3 |
| **Errors** | `401`, `403`, `422` |
| **Authorization** | Any authenticated user |
| **Ownership** | **`where('notifiable_type', User::class)->where('notifiable_id', $me->id)`** — always. Never a notifiable id from the request. This is the single most important check on this endpoint. |

Laravel's notifications table is not paginated natively; the standard paginator
wrap must be applied manually. Order `created_at desc`.

**Open:** which notification types exist and what triggers them (D-16). The
stored `type` is a PHP class FQCN — **map it to a stable string discriminator
on the wire** rather than leaking internal class names to the client.

---

#### `POST /notifications/{id}/read` · `POST /notifications/read-all`

| Dimension | Specification |
|---|---|
| **Endpoint** | `/api/notifications/{id}/read`, `/api/notifications/read-all` |
| **Method** | `POST` |
| **Authentication** | Required |
| **Ability** | `mobile` |
| **Request fields** | `id` — **UUID, not an integer** |
| **Validation** | `id` must be a valid UUID |
| **Response** | `200`, §3.1. `read-all` returns `{ success: true, message: "...", data: { marked: <int> } }` |
| **Errors** | `401`, `403`, `404` |
| **Authorization** | Any authenticated user |
| **Ownership** | Scoped to `$me` **on the update query itself**, not by fetch-then-check. `read-all` MUST be a single scoped `UPDATE`, never a read of all rows followed by per-row writes. |

**Routing note:** `read-all` must be registered **before** `{id}` or it will be
captured by the UUID route and fail to bind.

---

### 5.8 Messages

`messages` is a flat table — `sender_id`, `receiver_id`, optional `listing_id`,
`read_at`. There is **no conversation table** and none is to be added
(functional documentation §8.1). Conversations are **derived**.

---

#### `GET /messages/conversations`

| Dimension | Specification |
|---|---|
| **Endpoint** | `/api/messages/conversations` |
| **Method** | `GET` |
| **Authentication** | Required |
| **Ability** | `mobile` |
| **Request fields** | `page`, `per_page` |
| **Validation** | As §5.7 |
| **Response** | `200`, §3.2. `data.conversations` = `{ user: {id,name}, last_message: {...}, unread_count, updated_at }` |
| **Errors** | `401`, `403` |
| **Authorization** | Any authenticated user |
| **Ownership** | Derived strictly from `sender_id = $me->id OR receiver_id = $me->id`, grouped by the counterpart. No conversation record may include a user who is not $me or the counterpart. |

**Deriving this from a flat table requires a self-join or a
"latest message per counterpart" subquery.** It is the most expensive endpoint
in this proposal. Confirm the approach is acceptable before building.

**Open (D-17):** whether messaging requires a verified seller, an existing
transaction, or a listing context (§8.2). This changes who may appear in the
conversation list at all.

---

#### `GET /messages/conversations/{user}`

| Dimension | Specification |
|---|---|
| **Endpoint** | `/api/messages/conversations/{user}` |
| **Method** | `GET` |
| **Authentication** | Required |
| **Ability** | `mobile` |
| **Request fields** | `user` (int, the counterpart)<br>`listing_id` (int, optional filter)<br>`page`, `per_page` |
| **Validation** | `user` `required`,`integer`,`exists:users,id`<br>`listing_id` `sometimes`,`integer`,`exists:listings,id` |
| **Response** | `200`, §3.2. `data.messages` = message objects, oldest first |
| **Errors** | `401`, `403`, `404` |
| **Authorization** | Any authenticated user |
| **Ownership** | **`(sender_id = $me->id AND receiver_id = :user) OR (sender_id = :user AND receiver_id = $me->id)`.** Anything else is `404`. There is no path by which a user reads a message they are not a party to. |

A user must not be able to pass their own id as `:user` and read a
self-conversation. D-18.

---

#### `POST /messages`

| Dimension | Specification |
|---|---|
| **Endpoint** | `/api/messages` |
| **Method** | `POST` |
| **Authentication** | Required |
| **Ability** | `mobile` |
| **Request fields** | `receiver_id` (int, required)<br>`body` (string, required)<br>`listing_id` (int, optional) |
| **Validation** | `receiver_id` `required`,`integer`,`exists:users,id`, **`not_in:` the sender's own id**<br>`body` `required`,`string`,`max:5000`<br>`listing_id` `sometimes`,`integer`,`exists:listings,id` |
| **Response** | `201`, §3.1, the created message |
| **Errors** | `401`, `403`, `404` receiver not found, `409` self-message, `422` |
| **Authorization** | Any authenticated user — subject to D-17 |
| **Ownership** | **`sender_id = $me->id`, server-set.** `sender_id` is `#[Fillable]` and must be stripped from the request. A client-supplied `sender_id` would allow impersonation — F-10. `read_at` is likewise server-controlled. |

**Open (D-19):** whether an `id_document`-free open message graph permits spam
or abuse, and whether any rate limit or block mechanism is required. None
exists.

---

#### `POST /messages/read`

| Dimension | Specification |
|---|---|
| **Endpoint** | `/api/messages/read` |
| **Method** | `POST` |
| **Authentication** | Required |
| **Ability** | `mobile` |
| **Request fields** | `message_ids` (array of ints, optional — omit to mark the whole conversation read) |
| **Validation** | `message_ids` `sometimes`,`array`<br>`message_ids.*` `integer` |
| **Response** | `200`, §3.1 with `{ marked: <int> }` |
| **Errors** | `401`, `403`, `422` |
| **Authorization** | Any authenticated user |
| **Ownership** | **`UPDATE ... WHERE receiver_id = $me->id AND read_at IS NULL`** — scoped in the query. A client must not be able to mark a *sent* message as read, and must not mark another user's. |

---

### 5.9 Profile

---

#### `GET /profile`

| Dimension | Specification |
|---|---|
| **Endpoint** | `/api/profile` |
| **Method** | `GET` |
| **Authentication** | Required |
| **Ability** | `mobile` |
| **Request fields** | None |
| **Validation** | N/A |
| **Response** | `200`, §3.1. `data` = `UserResource` |
| **Errors** | `401`, `403` |
| **Authorization** | Any authenticated user |
| **Ownership** | `$me` only |

Functionally identical to `GET /auth/me`. Provided because clients look for it;
**if that is not wanted, drop this endpoint rather than duplicating the
resource.** D-20.

---

#### `PATCH /profile`

| Dimension | Specification |
|---|---|
| **Endpoint** | `/api/profile` |
| **Method** | `PATCH` |
| **Authentication** | Required |
| **Ability** | `mobile` |
| **Request fields** | `name` (optional)<br>`email` (optional)<br>`current_password` (required **iff** `password` or `email` is present)<br>`password` (optional)<br>`password_confirmation` (required **iff** `password` is present) |
| **Validation** | `name` `sometimes`,`string`,`max:255`<br>`email` `sometimes`,`string`,`email`,`max:255`,`unique:users,email,{$me->id}`<br>`password` `sometimes`,`string`,`min:8`,`confirmed`<br>`current_password` `required_with:password`,`current_password` |
| **Response** | `200`, §3.1, updated `UserResource` |
| **Errors** | `401`, `403`, `422` including `current_password` mismatch |
| **Authorization** | Any authenticated user |
| **Ownership** | `$me` only. |

**`role` and `seller_capability` are NOT updatable here.** They are `#[Fillable]`
(`User.php:17`), so mass assignment will accept them unless the request class
explicitly permits only `name`, `email`, `password`. **This is the highest-value
single guard in the mobile API** — accepting `seller_capability: "seller"` on
this endpoint would let any user grant themselves seller capability and bypass
seller verification entirely, which directly violates functional documentation
§2.6 and **[SEC] §4.5.1**. F-11.

A request containing either field returns `422`. It is **not** silently dropped —
see the §6.2 matrix.

**Open:** whether an email change requires re-verification (D-21). It currently
cannot be verified at all — see F-04.

---

## 6. Endpoint summary

### 6.1 Endpoint inventory

| Method | Path | Auth | Ability | Gate |
|---|---|---|---|---|
| `POST` | `/auth/register` | — | — | public |
| `POST` | `/auth/login` | — | — | public, `role=user` |
| `GET` | `/auth/me` | yes | `mobile` | — |
| `POST` | `/auth/logout` | yes | `mobile` | — |
| `GET` | `/listings` | yes | `mobile` | `active`/`sold` only |
| `GET` | `/listings/{listing}` | yes | `mobile` | owner for non-public |
| `POST` | `/seller-verification` | yes | `mobile` | latest must be `rejected` |
| `GET` | `/seller-verification/me` | yes | `mobile` | own, latest only |
| `GET` | `/seller/listings` | yes | `mobile` | `isApprovedSeller` |
| `POST` | `/seller/listings` | yes | `mobile` | `isApprovedSeller`; **no `status`** |
| `POST` | `/seller/listings/{listing}/submit` | yes | `mobile` | seller + owner; `draft` only |
| `PATCH` | `/seller/listings/{listing}` | yes | `mobile` | seller + owner; **no `status`** |
| `DELETE` | `/seller/listings/{listing}` | yes | `mobile` | seller + owner; `draft`/`inactive` only |
| `POST` | `/seller/listings/{listing}/price-suggestion` | yes | `mobile` | seller + owner; **estimator blocked** |
| `GET` | `/transactions` | yes | `mobile` | buyer or seller |
| `POST` | `/transactions` | yes | `mobile` | buyer; seller derived |
| `GET` | `/transactions/{transaction}` | yes | `mobile` | counterparty |
| `POST` | `/transactions/{transaction}/cancel` | yes | `mobile` | either party; `pending` only |
| `POST` | `/transactions/{transaction}/complete` | yes | `mobile` | **BLOCKED — OQ-15** |
| `GET` | `/notifications` | yes | `mobile` | own |
| `POST` | `/notifications/{id}/read` | yes | `mobile` | own, UUID |
| `POST` | `/notifications/read-all` | yes | `mobile` | own |
| `GET` | `/messages/conversations` | yes | `mobile` | participant — **D-17** |
| `GET` | `/messages/conversations/{user}` | yes | `mobile` | participant |
| `POST` | `/messages` | yes | `mobile` | sender derived — **D-17** |
| `POST` | `/messages/read` | yes | `mobile` | `receiver_id = $me` |
| `GET` | `/profile` | yes | `mobile` | own |
| `PATCH` | `/profile` | yes | `mobile` | own; **no `role`/`seller_capability`** |

### 6.2 Per-endpoint security matrix — BINDING **[SEC]**

Derived fields that must **never** be accepted from a mobile request, and
therefore must be absent from every request allow-list. This is the
contract-level view of functional documentation §10.

| Endpoint | Method | Fields the client may set | Fields **rejected** if present | Derived server-side |
|---|---|---|---|---|
| `/auth/register` | `POST` | `name`, `email`, `password`, `password_confirmation`, `device_name` | `role`, `seller_capability` | `role=user`, `seller_capability=buyer` |
| `/profile` | `PATCH` | `name`, `email`, `current_password`, `password`, `password_confirmation` | **`role`, `seller_capability`** | — |
| `/seller-verification` | `POST` | `business_name`, `business_location`, `business_description`, `id_document_ref` | `user_id`, `status`, `reviewed_by`, `admin_note` | `user_id = $me` |
| `/seller/listings` | `POST` | listing content fields, `photos` | **`seller_id`**, **`status`** | `seller_id = $me`, `status = draft` |
| `/seller/listings/{id}` | `PATCH` | any listing content field | **`seller_id`**, **`status`** | — |
| `/seller/listings/{id}/submit` | `POST` | none | all | status `draft → pending` |
| `/transactions` | `POST` | `listing_id`, `quantity` | **`buyer_id`**, **`seller_id`**, `total_amount`, `status` | both ids, amount, `status=pending` |
| `/messages` | `POST` | `receiver_id`, `body`, `listing_id` | **`sender_id`**, `read_at` | `sender_id = $me` |

**Rules for every row:**

* A rejected field returns `422` — it is **not** silently dropped. Silently
  dropping hides a client bug; accepting it is a security defect.
* `POST /auth/login` and `POST /auth/logout` take no body fields beyond
  `email`/`password`/`device_name`.
* `GET` endpoints take filters only, never identity or authority.
* Every write endpoint has a dedicated Form Request. No request body may reach a
  mass-assignment call unfiltered.

**Highest-value single guard:** `PATCH /profile`. It is the one endpoint where a
client would plausibly try `{"seller_capability": "seller"}`, and
`seller_capability` is `#[Fillable]` on the model. Accepting it there would
bypass seller verification entirely — a direct violation of functional
documentation §2.6.

## 7. Findings in the current implementation

Verified against source. **F-01, F-02 and F-11 are the ones that matter most.**

| ID | Severity | Finding |
|---|---|---|
| **F-01** | High | **The `admin` Sanctum ability is never verified.** `AuthService::login()` issues `['admin']` (`AuthService.php:34`), but `EnsureUserIsAdmin` checks only `$user->isAdmin()` — the `role` column. The ability is decorative. A non-admin cannot reach admin routes, so there is no live exploit, but the intended defence-in-depth layer is absent. **Add `ability:admin` to the admin group; it costs one middleware alias and no controller changes.** |
| **F-02** | High | **There is no mobile login path.** `AuthService::login()` requires `isAdmin()` (`AuthService.php:28`) and returns `null` for everyone else. A mobile user cannot obtain any token. This is the M1 blocker, and reusing this method would issue admin-authority tokens to mobile users. |
| **F-11** | High | **Authority and ownership fields are mass-assignable.** `#[Fillable(['name','email','password','role','seller_capability'])]` (`User.php:17`), plus `Listing.seller_id`, `Transaction.buyer_id`, `Transaction.seller_id` and `Message.sender_id`. A request class that passes these through lets a client set its own `seller_capability` to `seller`, bypassing verification (§2.6). **Now a binding approved requirement — see [SEC] §4.5 and the §6.2 matrix. Every mobile write endpoint needs an explicit allow-list, and rejected fields must 422 rather than be dropped.** |
| **F-08** | High | **Seller email addresses leak to every marketplace reader.** `ListingResource` embeds `seller.email` (`ListingResource.php:19-23`); `TransactionResource` embeds `buyer.email` and `seller.email`; `SellerVerificationResource` embeds `seller.email`. **Now a binding approved requirement — see [SEC] §10.4 and §8.1. Admin resources stay admin-oriented; mobile gets its own public projections.** |
| **F-09** | Medium | **No guard against duplicate open verifications, and no "latest record" resolution.** `AdminSellerVerificationRepository::list()` returns every record ordered by `created_at desc` with no dedupe (line 23), and `AdminSellerVerificationService::approve()`/`reject()` act on **whatever record is passed** without checking it is the seller's most recent (lines 28, 46). With the history rule (§3.2), approving a stale record would re-grant `seller_capability` after a newer rejection. `SellerVerificationStatus::isOpen()` exists but is unused. |
| **F-09b** | Medium | **`reject()` does not revoke seller capability.** `AdminSellerVerificationService::reject()` (line 46) updates the record but never touches `seller_capability`. If an approved seller is ever re-reviewed and rejected, they remain a seller. `approve()` does set it (line 38). Asymmetric. |
| **F-12** | Medium | **Sanctum tokens never expire.** `config/sanctum.php` sets `'expiration' => null`. A stolen mobile token is valid indefinitely, and logout is the only revocation. D-11/OQ-11. |
| **F-13** | Medium | **Listing `photos` is stored but never exposed.** The column exists and is `NOT NULL` (`listings` migration), but `ListingResource` omits it — 15 fields, none of them `photos`. A mobile listing screen would render no images. No upload endpoint, storage disk, or URL scheme exists. D-10. |
| **F-10** | High | **No listing publication path — now REQUIRED by [D-02].** `GET /api/admin/listings` is the only listing route (`routes/api.php:27`); admin can read listings but cannot change any status. [D-02] rule 8 requires admin approval before `active`, so `approve`, `reject` and `deactivate` endpoints are mandatory and **do not exist**. Specified in §5.4b. Functional doc OQ-14. |
| **F-04** | Medium | **`email_verified_at` is permanently null.** `MustVerifyEmail` is commented out (`User.php:5`) and nothing sets the column, yet `UserResource` exposes `email_verified_at` (line 23). The API advertises a verification state that can never be true. |
| **F-05** | Low | **Error bodies have no `success` field.** Success responses set `success: true`; Laravel's default errors do not. A client that checks `body.success` will treat every error as malformed. Mobile should branch on HTTP status, not on `success`. |
| **F-06** | Low | **`GET /api/user` returns the raw User model** (`routes/api.php:15-17`) — not a resource, and behind `auth:sanctum` with **no ability check**. Any Sanctum token, including a future mobile token, can call it. It duplicates `/auth/me` and bypasses the intended resource shape. |
| **F-14** | Low | **`AdminUserResource` is byte-identical to `UserResource`** — same 8 fields, same 28 lines. Dead code; a second definition to keep in sync. |
| **F-15** | Low | **No `MessageResource` or `NotificationResource` exists.** `backend/app/Http/Resources/` has no message or notification resource, and no mobile read request classes. Both are net-new work. |
| **F-16** | Info | **CORS allows only `http://localhost:5174`** (`config/cors.php`) — the Admin Web. **This is correct and requires no change**: native mobile clients are not subject to CORS. Recorded so it is not "fixed" later by mistake. |

## 8. Proposed resource shapes

### 8.1 Principle — BINDING **[SEC]**

**Do not blindly reuse Admin Web resources for mobile responses** (functional
documentation §10.4).

The existing resources are **administrator views**. Reusing them on mobile
re-exposes data the mobile app has no business showing (F-08). Introduce
**mobile-specific resources or response structures** where necessary.

* **Marketplace seller information exposes only fields appropriate for
  marketplace users.** Do not expose private seller email addresses through
  public marketplace responses.
* **Admin resources remain admin-oriented.** They are not a shared base to be
  trimmed per client.
* A stripped `ListingResource` shared by both clients would eventually get its
  fields re-added for the Admin Web and silently re-leak. That is the specific
  failure this rule exists to prevent.
* A mobile response must never carry administrator-only data: reviewer
  identities, internal notes, or unrelated users' contact details.

### 8.2 `ListingResource` (mobile)

Reuse the existing field set, with three changes:

```json
{
  "id": 12,
  "seller": { "id": 4, "name": "Juan Dela Cruz" },
  "livestock_type": "Cattle",
  "breed": "Maltese",
  "age_value": 18, "age_unit": "month",
  "gender": "female",
  "weight_value": 320.5, "weight_unit": "kg",
  "quantity": 8,
  "asking_price": "42500.00",
  "location": "Mabalacat, Pampanga",
  "health_status": "Healthy",
  "vaccination": "Brucellosis, FMD",
  "short_description": "…",
  "additional_notes": "…",
  "photos": [],
  "status": "active",
  "price_suggestion": null,
  "created_at": "2026-09-20T04:12:33.000000Z",
  "updated_at": "2026-09-20T04:12:33.000000Z"
}
```

| Change | Reason |
|---|---|
| **`seller.email` removed** | F-08, [SEC] §10.4. Marketplace browsing must not harvest seller emails. |
| **`photos` added** | F-13 + functional doc §4.5. The mobile API **must** expose photos, and **the schema must not change to make that possible** — the JSON column is sufficient. Representation settled at implementation (**D-10**). |
| `asking_price` as a **string** | §3.4. Never a float. |
| **No admin-only fields** | `status` here reflects the *owner's* listing. Never expose reviewer or internal data. |

`price_suggestion` is present **only** on the owner-scoped response, and only if
D-13 permits a buyer to see it. It is `null` for a buyer under the current
proposal.

### 8.3 `NotificationResource` (mobile) — new

```json
{
  "id": "9f1c1f2e-…-uuid",
  "type": "transaction_request",
  "data": { "listing_id": 12, "transaction_id": 5 },
  "read_at": null,
  "created_at": "2026-09-20T04:12:33.000000Z"
}
```

* `id` is a **UUID string**.
* `type` is a **stable string discriminator**, mapped from the stored PHP class
  FQCN. The client must never receive a class name.
* `data` is parsed from the stored JSON text into a real object. Its shape
  depends on D-16, which is unresolved.

### 8.4 `MessageResource` (mobile) — new

```json
{
  "id": 88,
  "sender": { "id": 4, "name": "Juan Dela Cruz" },
  "receiver": { "id": 9, "name": "Maria Santos" },
  "listing": { "id": 12, "livestock_type": "Cattle", "breed": "Maltese" },
  "body": "…",
  "listing_id": 12,
  "read_at": null,
  "created_at": "2026-09-20T04:12:33.000000Z"
}
```

No email addresses on either party (F-08).

### 8.5 `TransactionResource` (mobile)

As §8.2 — reuse the existing fields, drop `buyer.email` and `seller.email`,
serialise `total_amount` as a string.

## 9. Remaining open decisions

### 9.1 Closed by the decision round

| Was | Now | Resolution |
|---|---|---|
| D-02 | **[D-02]** | Listing publication is **settled and implemented into this contract**: moderated lifecycle, seller cannot self-publish, `submit` endpoint, admin moderation endpoints, `active`-only browse. |
| D-03 | **[D-03] / OQ-03** | Price-suggestion *constraints* are settled (dedicated service, no invented algorithm, no ML claims, seller owns the price). The **estimation method itself is still open** — see 9.2. |
| D-15 | **[D-15] / OQ-15** | Transaction states, both transitions, terminality, two-party cancellation and buyer-initiated creation are settled. **The completion-confirmation actor is still open** — see 9.2. |
| — | **[SEC]** | Mass-assignment exposure (F-11) and admin-resource email leakage (F-08) are now binding approved requirements, not findings awaiting a decision. |
| D-16 (photos) | **D-10** | Partly closed: **no schema change permitted**, and the mobile API **must** expose photos. Upload mechanism and URL scheme remain open. |

### 9.2 Still blocking implementation

| ID | Decision | Blocks |
|---|---|---|
| **OQ-15** (D-15) | **Who performs transaction completion confirmation, and what constitutes it** — seller, buyer, or mutual agreement? [D-15] rule 4 says "the appropriate transaction confirmation" without naming it. | `POST /transactions/{id}/complete` **only.** Everything else in §5.6 is buildable. |
| **OQ-03** (D-03) | **The estimation method.** [D-03] mandates a dedicated service and forbids inventing an algorithm, but no algorithm, model, or integration exists. Must be documented before the production estimator. | The **interior** of the price-suggestion service. The endpoint contract in §5.5 is buildable. |
| **OQ-14** | **Admin listing moderation endpoints.** [D-02] makes admin approval mandatory, but admin can only read listings today. Specified in §5.4b; needs building. | The `active` half of the lifecycle. Not mobile surface. |
| **D-10** | **Listing photo representation** — upload mechanism, storage, URL scheme, exact mobile shape. Constrained: no schema change (§4.5). | Photo *upload*; photo *read* shape depends on it. |
| **D-11** | **Token lifetime.** `config/sanctum.php` has `expiration => null` (F-12). | Shipping to production, not first implementation. |
| **D-17** | **Messaging eligibility.** Verified seller, existing transaction, or listing context? | §5.8 |
| **D-16** | **Which notification types exist, and what triggers them?** | §5.7 payloads |
| **D-12** | **Soft or hard delete for listings?** No `deleted_at` exists, and a `sold` listing is part of a completed transaction record. | `DELETE /seller/listings/{id}` |
| **OQ-16** (D-02) | **`inactive → active` reactivation.** [D-02] defines no path back to `active`. Does a rejected listing need a fresh `draft → pending` cycle, or is it dead? | Post-rejection seller flow |
| **OQ-17** (D-02) | **Quantity exhaustion.** What happens to an `active` listing when its `quantity` is fully transacted? Auto-`sold`? Left `active`? | Transaction quantity handling |
| **D-25** | **`DELETE` vs `active → inactive`.** Deleting an `active` listing is functionally self-deactivation, which [D-02] reserves to admin. | `DELETE /seller/listings/{id}` |
| **D-24** | **Editing a non-`draft`, non-`active` listing.** Is a `pending` listing editable while awaiting review? A `sold` or `inactive` one? | `PATCH /seller/listings/{id}` |
| **D-23** | **Direct access to a `sold` listing.** Not in the marketplace list ([D-02] rule 9), but still viewable by URL? | `GET /listings/{listing}` |
| **D-13** | **May a buyer see the price-suggestion range** on a listing? | §5.5, §8.2 |
| **D-18** | **Self-conversations** — forbid or allow? | `GET /messages/conversations/{user}` |
| **D-19** | **Messaging abuse controls** — rate limits, blocking, reporting? None exist. | `POST /messages` |
| **D-21** | **Does an email change require re-verification?** `MustVerifyEmail` is not even enabled (F-04). | `PATCH /profile` |
| **D-01** | **Does registration return a token**, or require a login round-trip? | `POST /auth/register` |
| **D-22** | **Is registration open to the public**, or invite-only? *(renamed from the old colliding D-02b)* | `POST /auth/register` |
| **D-03b** | **May a `role = admin` account authenticate via mobile at all?** [SEC] settles that such a token is never admin-authority; it does not settle whether it may exist. | `POST /auth/login` |
| **D-05** | **May signed-out visitors browse the marketplace?** | `GET /listings` |
| **D-04** | **Logout scope:** current token (proposed) or all devices? | `POST /auth/logout` |
| **D-07** | **Should an already-approved seller be blocked from submitting** a new verification? | `POST /seller-verification` |
| **D-08** | **Should a seller see full verification history**, or only the latest? | `GET /seller-verification/me` |
| **D-20** | **Is `GET /profile` wanted**, given it duplicates `GET /auth/me`? | `GET /profile` |
| **D-09** | **Rate limits** for register, price-suggestion, messages. | §3.5 |

**D-06 is closed.** The resubmission guard — submission blocked while the latest
record is `submitted`/`pending_review`, permitted only after `rejected` — follows
directly from functional documentation §3.2 and is now reinforced by the
explicit rule that a user cannot become a seller by modifying their own account
fields. Implement as specified.

### 9.3 Non-blocking implementation notes

| Item | Note |
|---|---|
| Verify Sanctum's `ability`/`abilities` aliases exist on the installed version | If absent, one small middleware class is needed |
| `decimals` casts on `asking_price` / `total_amount` | Confirm the models return strings, not floats (§3.4) |
| `NotificationResource` + `MessageResource` | Net-new (F-15) |
| Mobile write-request classes | Net-new; each must allow-list fields (F-11) |
| Conversation derivation query | Self-join or correlated subquery; the costliest query in the contract |
| `GET /api/user` | Remove or admin-gate (F-06) |
| `AdminUserResource` | Delete as dead code (F-14) |
| CORS | **Do not change** (F-16) |

## 10. Verification status

| Area | State |
|---|---|
| Approved functional rules | **Aligned.** D-02, D-03, D-15 and [SEC] are incorporated into §4, §5, §6 and §8. |
| Listing publication | **Settled and specified** (§5.4, §5.4b). **Admin moderation endpoints still missing** — OQ-14 / F-10. |
| Seller cannot self-publish | **Enforced by contract** — `status` is not a request field; `submit` is the only seller transition. |
| Transaction lifecycle | **Settled except the completion actor** — `cancel` implementable, `complete` blocked on OQ-15. |
| Price estimation | **Constraints settled; method still undefined** — OQ-03. No algorithm, model or integration exists, and none may be invented. |
| Mass-assignment exposure | **Binding requirement defined** (§4.5, §6.2). **Not yet implemented** — F-11 remains open in the code. |
| Admin-resource email leakage | **Binding requirement defined** (§8.1). **Not yet implemented** — F-08 remains open in the code. |
| Token expiry policy | **Unspecified** — F-12 / D-11 |
| Email verification | **Unimplemented** — F-04 |
| Listing photo delivery | **Stored, not exposed** — F-13. Schema change now forbidden. |
| Mobile auth | **Does not exist** — F-02 |
| Messaging | **No resources, no endpoints** — F-15 |
| Notifications | **No resources, no endpoints** — F-15 |

**Note the two rows in bold type above.** D-02/D-03/D-15 decided the *contract*;
they did not change a single line of Laravel. F-11 and F-08 are now approved
requirements that the backend still violates, and they must be fixed **before**
any mobile write endpoint ships — not alongside the first feature.

## 11. Implementation sequencing — after approval only

Do not begin until §9.2 is answered for the phase in question and this document
is approved.

1. **Security foundations [SEC]** — write-request base with field allow-listing
   and 422-on-rejected-field; mobile resource projections; `decimal:2` casts.
   **Do this first.** Every later step creates write endpoints, and F-11 is an
   open privilege-escalation path until it is closed.
2. **Harden** — F-01 `ability:admin` on the admin group; scope or remove
   `GET /api/user` (F-06); delete `AdminUserResource` (F-14).
3. **Auth** — §5.1 only. The M1 blocker. Separate service, mobile ability, admin
   flow untouched (§10.5).
4. **Seller verification** — §5.3. Small, unblocks the seller path.
5. **Marketplace + own listings** — §5.2, §5.4, §5.4b. Needs the admin
   moderation endpoints (OQ-14) before `active` is reachable, and D-10 for
   photos.
6. **Profile** — §5.9.
7. **Transactions** — §5.6 minus `complete`. Blocked only on OQ-15 for the
   final transition.
8. **Messages, notifications** — §5.7, §5.8. Subject to D-16 and D-17.
9. **Price suggestion** — §5.5 interface and service boundary. The estimator
   interior stays blocked on OQ-03.

Steps 1–3 are the M1 milestone. **Step 1 is a prerequisite of steps 4–9**, not
a parallel task.

## 12. Related

* `docs/AGROBENTA_FUNCTIONAL_DOCUMENTATION.md` — **approved**, and authoritative
  over this document.
* `docs/AGENTS.md` — documentation rules.
* `mobile/AGENTS.md` — mobile-side guidance and the M0 API gap register.
* `backend/routes/api.php` — current API surface.
