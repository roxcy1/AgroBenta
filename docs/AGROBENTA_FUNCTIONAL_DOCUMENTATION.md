# AgroBenta — Functional & System Documentation

**Status: APPROVED** (approved during project planning, extended by a later
explicit business-decision round)

---

## 0. Provenance and status — read this first

This document is the repository's copy of the AgroBenta functional/system
documentation that was **approved during project planning**.

It is a **transcription into the repository**, not the planning original. The
planning original is not stored in Git; that is a documentation/governance gap,
tracked as **DG-01** in §13.

### 0.1 Decision round

A later round of business decisions was approved explicitly, before any mobile
API implementation began. Those decisions are now locked into this document and
are marked **[D-nn]** at the relevant rule:

| Decision | Subject | Where |
|---|---|---|
| **D-02** | Listing publication lifecycle | §4.4 |
| **D-03** | AI price suggestion constraints | §5 |
| **D-15** | Transaction status and lifecycle | §6.4 |
| **SEC** | Authorization-sensitive fields, request allow-lists, mobile resource separation | §10 |

These are **approved rules, not proposals.** They resolved open items OQ-01,
OQ-02, OQ-03, and part of OQ-09, which are marked closed in §13.

### What that means for you

* Every rule below is an **approved business rule**. It is authoritative under
  the source-of-truth order in the root `AGENTS.md`.
* Where this document and the Laravel implementation disagree, **both** are
  recorded in §12 and in `MOBILE_API_CONTRACT_PROPOSAL.md`. Neither is
  silently changed.
* Sections marked **[CONFIRM]** are transcribed from an approved rule summary
  but the **exact planning wording was not available** at transcription time.
  The rule is not in doubt; the precise phrasing is. Confirm against the
  planning original before treating any wording here as quotable.
* Rules marked **[D-nn]** were decided explicitly and their wording **is**
  quotable.
* Where a decision was approved but left a genuine gap, the gap is recorded as
  an open item in §13. **The gap is documented, not filled by invention.**
* Nothing in this document may be edited to settle an argument. Report a
  conflict instead.

### Approved terminology — do not substitute

| Use | Never use |
|---|---|
| "Become a Seller" | "Switch to Seller" |
| "buyer" / "seller" (`seller_capability`) | "buyer mode" / "seller mode" |
| "role" / "seller capability" | "account type" |
| "verification" / "seller verification" | "seller approval request" as a user-facing term |

---

## 1. Purpose and scope

AgroBenta is a livestock marketplace connecting **buyers** and **sellers**, with
**seller verification** as the trust mechanism and **AI price suggestion** as a
decision aid.

Three applications:

| Application | Stack | Responsibility |
|---|---|---|
| Backend | Laravel REST API + MySQL | All business logic, authorization, data |
| Admin Web | React + Vite | Administrator and staff workflows |
| Mobile | Flutter | Buyer, seller and seller-verification workflows |

The **backend is the only place business rules are enforced.** Neither client
may implement a rule the server does not enforce.

---

## 2. Single-account model

**Every person has exactly one account. That account does not change when the
person becomes a seller.**

```text
register ──> buyer                      role          = user
                │                        seller_capability = buyer
                │
                │ user chooses "Become a Seller"
                ▼
           seller verification          status = submitted
                │
           admin reviews
                ▼
             approved ──> seller        role          = user
                                         seller_capability = seller
```

### 2.1 Initial state

Every registered user starts as a **buyer**. This is the default and is never
negotiable at registration time.

### 2.2 The user-facing action

The only user-facing action for this transition is:

> **"Become a Seller"**

A buyer may choose to become a seller at any time by submitting seller
verification (§3).

### 2.3 Explicitly prohibited

* A separate buyer account and a separate seller account.
* A "Switch to Seller" control, toggle, or mode.
* A second login, second token, or second user id for seller activity.
* Any client-side notion of "the current role" that the server does not hold.

The account a user registers with is the account they transact from, permanently.

### 2.4 Role vs seller capability

These are **two independent fields** and must not be conflated.

`role` — authorisation to administer the platform:

| Value | Meaning |
|---|---|
| `user` | A platform user. The default. |
| `admin` | An administrator. Staff only. |

`seller_capability` — marketplace selling rights:

| Value | Meaning |
|---|---|
| `buyer` | Not a seller. The default. |
| `seller` | Approved seller. Selling rights granted. |

### 2.5 The four valid combinations

| `role` | `seller_capability` | Valid | Meaning |
|---|---|---|---|
| `user` | `buyer` | ✅ | Registered buyer. The default state. |
| `user` | `seller` | ✅ | **Approved seller.** The normal seller. |
| `admin` | `buyer` | ✅ | Administrator who does not transact. |
| `admin` | `seller` | ✅ | Administrator who is also an approved seller. |

An **approved seller** is `role = user` **and** `seller_capability = seller`.
Selling rights come from `seller_capability` alone; `role` is irrelevant to them.

An **administrator** is `role = admin`, regardless of `seller_capability`.

### 2.6 Granting seller capability

`seller_capability` becomes `seller` **only** when a seller verification is
**approved** (§3). It is never set directly by the user, by a client, or by a
registration request.

**[SEC] A user cannot become a seller merely by modifying their own account
fields.** Specifically:

* A registration request must not be able to set `role` or `seller_capability`.
  New accounts are always `role = user`, `seller_capability = buyer` (§2.1).
* A profile update must not be able to set `role` or `seller_capability`.
* Neither field is ever accepted from an untrusted mobile request. See §10.

Seller capability is granted **only** through the approved verification
workflow. There is no other path to it.

---

## 3. Seller verification

The trust mechanism. A user becomes a seller by submitting verification that an
administrator reviews.

### 3.1 States

Exactly four. These are the only permitted values.

| State | Meaning |
|---|---|
| `submitted` | Submitted by the user. Not yet picked up by an administrator. |
| `pending_review` | Under administrator review. |
| `approved` | Approved. `seller_capability` becomes `seller`. |
| `rejected` | Rejected. `admin_note` explains why. |

`submitted` and `pending_review` are **open** states: a review is in flight.

### 3.2 The resubmission rule

> **A rejected verification may be resubmitted. Resubmission creates a new
> record. Previous records are preserved as history.**

This is load-bearing and is easy to get wrong:

* A user may hold **multiple** verification records over time.
* Each submission is a **new row**. An existing record is never updated back to
  `submitted`, and a rejected record's history is never overwritten.
* A new submission is permitted **only** when the user's most recent
  verification is `rejected`. A user with an open (`submitted` or
  `pending_review`) verification cannot submit again.
* The user's current verification state is their **most recent** record, not
  their first and not an arbitrary one.
* `seller_capability` is derived from the most recent record.

### 3.3 What verification carries

| Field | Required | Notes |
|---|---|---|
| `business_name` | yes | |
| `business_location` | no | |
| `business_description` | no | |
| `id_document_ref` | no | **A reference, not the document itself.** No identity document is uploaded or stored. |
| `admin_note` | — | Written by the administrator. Shown to the user on `rejected`. |

---

## 4. Livestock listings

The marketplace inventory unit. Owned by exactly one seller.

| Aspect | Rule |
|---|---|
| Ownership | Exactly one seller per listing. |
| Ownership assignment | Set by the server from the authenticated user. **Never accepted from the client.** |
| Status | `draft`, `pending`, `active`, `sold`, `inactive`. |
| Default status | `draft`. |
| Price | `asking_price`, set by the seller. |
| Quantity | Whole units, at least 1. |
| Species | `livestock_type`, free text. |
| Location | Single free-text string. |
| Age | `age_value` + `age_unit` (`day`/`month`/`year`). Both optional. |
| Weight | `weight_value` + `weight_unit` (`kg`/`lb`). |
| Gender | `male`/`female`. Optional. |
| Health | `health_status`, free text. Optional. |
| Vaccination | `vaccination`, free text. Optional. |
| Photos | `photos`, JSON. |

### 4.1 `livestock_type` is free text

`livestock_type` is a plain string. It is **not** an enum and **must not** become
one without explicit approval. A controlled vocabulary is desirable for
filtering and is listed as an open item (**OQ-04**) — but adding an enum now
would change approved data design.

### 4.2 Only approved sellers may create listings

Creating or managing a listing requires `seller_capability = seller`. A buyer
browsing the marketplace is not thereby able to list livestock.

### 4.3 Price is the seller's decision

`asking_price` is set by the seller. The AI price suggestion (§5) informs that
decision and never sets it (§5.2).

### 4.4 Publication lifecycle **[D-02]**

A listing moves through a fixed lifecycle. Publication is a **moderated
process**: a seller cannot self-publish.

```text
  DRAFT ──submit──> PENDING ──admin approve──> ACTIVE ──> SOLD
                      │                          │
                      └──admin reject──> INACTIVE<┘
```

**Permitted transitions — and only these:**

| From | To | Who |
|---|---|---|
| `draft` | `pending` | **Seller** submits for review |
| `pending` | `active` | **Admin** approves |
| `pending` | `inactive` | **Admin** rejects |
| `active` | `inactive` | **Admin** deactivates |
| `active` | `sold` | Seller, on completed sale |
| `pending` | `draft` | **Not permitted** — see ambiguity A-01 |
| `inactive` | `active` | **Not permitted** — see ambiguity A-02 |
| `sold` | anything | **Not permitted.** `sold` is terminal. |

**Approved rules:**

1. **Draft listings are private to the seller.** Not visible to buyers, not
   visible in the buyer marketplace, and not enumerable by any other user.
2. **Pending listings have been submitted for review and are not visible in the
   buyer marketplace.**
3. **Active listings are approved and visible in the buyer marketplace.**
4. **Sold listings are no longer available for new transactions.**
5. **Inactive listings are not publicly available.**
6. **A seller cannot directly set a listing to `active`.** There is no request
   path, and no client may send it.
7. **Seller submission moves a valid draft to `pending`.** "Valid" means the
   listing satisfies the field requirements in §4 — a submission that would not
   produce a valid listing must be rejected, not queued.
8. **Administrator approval is required before a listing becomes `active`.**
9. **Buyers can browse only `active` listings.**

**Consequences that follow from these rules:**

* Seller create sets `draft`. A seller **never** sends `status` at all — the
  server sets it, and the only status a seller may cause is `pending` via
  submission.
* The buyer marketplace query filters to `active` server-side. It is not a
  client-supplied filter.
* `inactive` and `draft` and `pending` are all invisible to buyers, but for
  different reasons: `draft` is the seller's own unfinished work, `pending` is
  in review, `inactive` was removed from sale.
* Because approval is required, **the Admin Web needs a listing
  approve/reject capability that does not exist today** — see §13, OQ-14.

**Do not invent additional listing states.** The five above are the complete
set, and they match the existing `listings.status` enum exactly. No sixth state,
no renamed state.

### 4.5 Listing photos **[SEC]**

`listings.photos` is stored as **JSON** and already exists. The approved rules:

* The mobile API **must expose listing photos** to the marketplace.
* **Do not change the database schema** in order to expose the existing photos.
  The column is sufficient.
* The correct mobile response representation is to be **determined during
  implementation** (§13, OQ-09) — it is not fixed by this decision.

The representation must not be decided by copying the admin view, and must not
require a schema migration.

---

## 5. AI price suggestion

### 5.1 Purpose

A **decision-support and reference aid** for sellers when choosing an asking
price.

### 5.2 The seller decides

> The AI price suggestion is **decision-support and reference only**.
> **The seller determines the final asking price.**

Binding constraints:

* The suggestion **never** writes, overwrites, or defaults `asking_price`.
* A seller may accept, adjust, or ignore a suggestion, and **may list without
  ever requesting one**.
* A suggestion is advisory output. It is not a valuation, a guarantee, an offer,
  or an authoritative price.
* A suggestion belongs to a specific listing and records the inputs it was
  produced from.

### 5.3 Output shape

A suggestion is a **range** with a stated basis, not a single authoritative
number.

| Output | Meaning |
|---|---|
| `estimated_min` | Lower bound of the suggested range. |
| `estimated_max` | Upper bound of the suggested range. |
| `estimated_value` | Suggested / reference value within the range. |
| `basis` | Human-readable explanation of how the range was derived. |
| `input_snapshot` | The inputs the estimate was computed from, captured at request time. |
| `estimated_at` | When the estimate was produced. |

`basis` is **required to be meaningful**. A range with no stated basis is not
decision support.

### 5.4 Implementation constraints **[D-03]**

Approved rules governing how the estimation feature is built:

1. The system **may** generate: estimated minimum, estimated maximum, a
   suggested/reference value, and a basis/explanation. Those four outputs are
   the whole permitted output surface — nothing more.
2. The suggestion **does not** automatically determine the seller's asking
   price.
3. **The seller chooses the final asking price.**
4. **`listings.asking_price` remains the seller's final chosen price** at all
   times. The estimator never writes it.
5. **The estimation process must be implemented as a dedicated service.** It is
   not inline controller logic, and it is not a model method. The API layer
   calls a service; the service owns the estimation.
6. **Do not claim that a machine-learning model exists unless an actual
   model or integration has been implemented.** This applies to code, to
   comments, to commit messages, and to documentation. The feature is named
   "AI price suggestion"; the approved name is not evidence of a model.
7. **Do not invent an AI algorithm during the API implementation phase.**
8. **The estimation method must be explicitly documented before implementing the
   production estimator.**

**What rule 8 means in practice:** the API endpoint, its request, its response
shape, its authorization, and its persistence are specified and may be built.
The **interior** of the estimator — how `estimated_min` / `estimated_max` /
`estimated_value` are actually computed — is **not yet decided** and must not be
guessed at implementation time. A stub, a documented placeholder, or an
explicitly-failing "not yet implemented" path is acceptable; a plausible-looking
invented formula is not.

Until the method is documented (§13, OQ-03), the endpoint either returns a
clearly-labelled unavailable response or is not exposed at all. It must never
return a fabricated number.

---

## 6. Transactions

Records a completed commercial arrangement between a buyer and a seller.

| Aspect | Rule |
|---|---|
| Parties | Exactly one `buyer_id` and one `seller_id`, both `users`. |
| Listing | Exactly one `listing_id`. |
| Quantity | Whole units. |
| Amount | `total_amount`, fixed when the transaction is created. |
| Status | `pending`, `completed`, `cancelled`. |
| Default status | `pending`. |

### 6.1 Amount is server-computed

`total_amount` is derived by the server from the listing's `asking_price` and
the agreed `quantity`. **A client-supplied amount is never trusted or stored.**

### 6.2 Self-transaction

A user cannot be both buyer and seller on the same transaction.

### 6.3 No payment capture

A transaction records that an arrangement was reached. It is **not** evidence of
payment, and the system does not move money (§9.1).

### 6.4 Status and lifecycle **[D-15]**

Exactly three states: `pending`, `completed`, `cancelled`.

```text
  PENDING ──confirm──> COMPLETED     (terminal)
      │
      └──cancel──> CANCELLED         (terminal)
```

**Approved rules:**

1. **The buyer initiates a transaction.** A transaction is created by a buyer
   acting on a seller's listing. A seller does not create transactions.
2. **Newly created transactions start as `pending`.**
3. **A seller may view and manage transactions involving the seller's own
   listings** — and nothing else. Seller access is scoped by
   `transactions.seller_id`, which is server-derived from the listing, never
   from the request.
4. **Completion requires the appropriate transaction confirmation.**
5. **Pending transactions may be cancelled by the buyer or by the seller**,
   according to the API's defined cancellation operation. Both parties may
   cancel; neither may cancel a non-`pending` transaction.
6. **`completed` is terminal.** No transition leaves it.
7. **`cancelled` is terminal.** No transition leaves it.
8. **No payment gateway is included in the initial scope.**
9. **No transportation or logistics processing is included in the initial
   scope.**
10. **Do not invent refund, payment, shipping, or delivery workflows.**

#### 6.4.1 What D-15 does and does not settle

Settled, and safe to implement:

* The three states, the two transitions, and their terminality (rules 1, 2, 6, 7).
* Cancellation by **either** party while `pending` (rule 5). The API defines the
  operation; the contract specifies it as
  `POST /transactions/{transaction}/cancel`.
* Seller scoping by `seller_id` (rule 3).

**Not settled — recorded as ambiguity, deliberately not invented:**

> **A-03 — who performs the completion confirmation, and what constitutes it.**
> Rule 4 requires "the appropriate transaction confirmation" without naming the
> actor or the event. It is not stated whether completion is confirmed by the
> seller, by the buyer, or requires mutual agreement, nor what evidence (if any)
> is required. **This must not be guessed.** The transaction feature may be
> built up to and including `pending` and `cancelled`; the `complete`
> transition stays unimplemented until this is answered. See §13, OQ-15.

Note that rules 8–10 make this narrow. There is no payment capture to confirm, no
delivery to await, and no refund to model, so the confirmation is a pure
agreement step between two parties — which is exactly why the actor has to be
stated rather than assumed.

### 6.5 Nothing downstream of completion

Because `completed` is terminal and there is no payment, shipping or delivery
scope (§6.4 rules 8–10), **there is no refund, reversal, payout, shipment,
delivery, or dispute state.** A completed transaction is a record that an
arrangement was reached and nothing more. Adding any post-completion state
requires a new approval.

---

## 7. Notifications

System-generated messages for a user.

| Aspect | Rule |
|---|---|
| Identity | A UUID, not a sequential integer. |
| Owner | Exactly one notifiable user. |
| Read state | `read_at`; `null` means unread. |
| Content | A JSON payload plus a type discriminator. |

A user may only ever read or act on **their own** notifications. Enumerating,
reading, or mutating another user's notifications is forbidden.

Which notification types exist, and what triggers them, is an open item
(**OQ-06**).

---

## 8. Messages

Direct messaging between users, optionally in the context of a listing.

| Aspect | Rule |
|---|---|
| Parties | Exactly one `sender_id` and one `receiver_id`. |
| Listing context | Optional. Messages may be listing-scoped or general. |
| Read state | `read_at`; `null` means unread. |
| Content | Plain text body. |

### 8.1 No conversation entity

There is **no conversation or thread record**. A conversation is *derived* from
the message history between a pair of users. No conversation table is to be
added without approval.

### 8.2 Participation

A user may read and send messages only where they are the sender or the
receiver. There is no third-party or anonymous access to a message.

Whether messaging requires a verified seller, a transaction, or a listing
context is an open item (**OQ-07**).

---

## 9. Admin Web vs Mobile responsibilities

### 9.1 There is no admin mobile application

**The administrator interface exists only in the Admin Web.** There is no admin
app, no admin section in the mobile app, and no admin role in the mobile client.

Administrative functions include reviewing seller verification, managing users,
viewing all listings and transactions, and reading reports and system activity.

### 9.2 Division

| Concern | Owner |
|---|---|
| Seller verification **review** (approve / reject) | Admin Web |
| Seller verification **submission** | Mobile |
| Marketplace browsing | Mobile |
| Listing creation and management | Mobile (approved sellers) |
| AI price suggestion | Mobile (approved sellers) |
| Transactions | Mobile (both parties) |
| Notifications | Mobile |
| Messages | Mobile |
| Own profile | Mobile |
| User administration | Admin Web |
| Reports and system activity | Admin Web |
| Platform settings | Admin Web |

### 9.3 The boundary is a security boundary

* The mobile app must not call admin endpoints.
* An **admin token must never authorise a mobile request**, and a **mobile token
  must never authorise an admin request.** These are separate authorisation
  contexts and must be separately enforced.
* Mobile must not reproduce admin authorisation rules. It consumes admin
  decisions; it does not make them.

---

## 10. Security requirements **[SEC]**

These are **approved requirements**, not recommendations. They apply to every
mobile write endpoint, and they are a precondition for implementing any of
them.

### 10.1 Authorization-sensitive fields are never client-controlled

The following fields decide **who a request acts as** or **what authority it
carries**. They must **never** be accepted from an untrusted mobile request.
Each is derived from the authenticated session or from a server-side
relationship.

| Field | Must be derived from |
|---|---|
| `users.role` | Never client-set. Assigned internally only. |
| `users.seller_capability` | The approved verification workflow (§2.6, §3) — never a request field. |
| `listings.seller_id` | The authenticated user. |
| `transactions.buyer_id` | The authenticated user. |
| `transactions.seller_id` | `listing.seller_id`, via the listing relationship. |
| `messages.sender_id` | The authenticated user. |

**A client must not be able to send:**

```json
{ "seller_capability": "seller" }
```

to become a seller. Nor may it specify another user's `seller_id` when creating
a listing, or another user's `buyer_id` when creating a transaction.

**Why this is a rule and not a code-review habit:** these fields are all
mass-assignable in the current implementation, so an unguarded request class
accepts them silently. The guard must be structural, not incidental.

### 10.2 Explicit request field allow-lists

Every mobile write endpoint must accept **only** an explicit list of fields.

* Use a dedicated Form Request per endpoint.
* Permit only the documented client-settable fields.
* Do **not** pass a request body through to a mass-assignment call.
* Do not rely on a denylist. A denylist fails open when a field is added later.
* Adding a field to a model must never silently make it client-settable.

### 10.3 Derived, not declared

Identity and ownership are **derived from the session and from relationships**,
never declared in the request body. This applies to reads as well as writes: a
resource path parameter is a *selector*, not proof of ownership, and the
ownership check still runs.

### 10.4 Mobile resource separation

**Do not blindly reuse Admin Web resources for mobile responses.**

* Create mobile-specific resources or response structures where necessary.
* **Do not expose private seller email addresses through public marketplace
  responses.** Marketplace seller information exposes only fields appropriate
  for marketplace users.
* Admin resources remain **admin-oriented**. They are not a shared base to be
  trimmed per-client; trimming a shared resource is how a field gets re-added
  for one client and silently re-exposed to the other.
* A mobile response must never contain data that only an administrator should
  see — reviewer identities, internal notes, other users' contact details.

### 10.5 Authentication separation

* **Mobile authentication must be separate from Admin Web authorization.**
* **Do not reuse the admin login flow.**
* **Do not issue admin-authority tokens to mobile users.**
* Mobile users receive a token appropriate for **regular user / mobile** access.

Reinforced by §9.3: an admin token must never authorise a mobile request, and a
mobile token must never authorise an admin request. Both directions are
enforced, independently.

---

## 11. Initial scope exclusions

The following are **explicitly out of scope** for the initial release. They are
not deferred features with designs in progress; they are not built at all.

| Excluded | Note |
|---|---|
| **Full online payment system** | No payment capture, processing, or settlement. A transaction records an arrangement, not a payment (§6.3). |
| **Transportation / logistics system** | No shipment tracking, delivery scheduling, or carrier integration. |
| **Separate admin mobile application** | (§9.1) |
| **Currency column** | No currency is stored. Amounts are as entered. **[CONFIRM]** |
| **`livestock_type` enum** | Free text unless explicitly approved later (§4.1). |
| **Conversation records** | Derived, not stored (§8.1). |
| **Identity document storage** | `id_document_ref` is a reference only (§3.3). |

**[CONFIRM]** on the currency row: the approved data design contains no currency
column and §12 asks for none to be added, but whether "amounts are implicitly
PHP peso" is itself an approved statement could not be verified from the
transcribed rules. The Admin Web formats amounts as `₱` / `en-PH`, which is
consistent with an implicit peso but is a client-side formatting choice, not
stored data.

---

## 12. Data design

The approved schema. **Preserve it.** These are the tables and their roles.

| Table | Purpose | Key relationships |
|---|---|---|
| `users` | All accounts | `role`, `seller_capability` |
| `seller_verifications` | Verification submissions and review history | many per `user` (§3.2) |
| `listings` | Marketplace inventory | one `seller_id`; many `photos` |
| `ai_price_estimates` | Price suggestion history | many per `listing` |
| `transactions` | Commercial arrangements | one `buyer_id`, one `seller_id`, one `listing_id` |
| `activities` | System activity log | one optional `user_id` |
| `messages` | Direct messages | `sender_id`, `receiver_id`, optional `listing_id` |
| `notifications` | Per-user notifications | one notifiable; UUID identity |
| `settings` | Platform settings | keyed |

### 12.1 Constraints on change

* Do **not** add a currency column. (§11)
* Do **not** create a `livestock_type` enum. (§4.1)
* Do **not** add a conversation table. (§8.1)
* Do **not** add a sixth listing state. The five in §4.4 are the complete set.
* Do **not** change the schema to expose listing photos. (§4.5)
* Do **not** make `seller_verifications.user_id` unique. It is one-to-many by
  the resubmission rule (§3.2), and a unique constraint would make resubmission
  impossible.
* Do **not** add a second account table, or split buyers and sellers into
  separate records. (§2.3)
* Preserve backward compatibility. Existing data must remain readable.

### 12.2 Implementation status

The schema above is fully implemented in `backend/database/migrations/` and
matches this document. Verified column by column — see
`MOBILE_API_CONTRACT_PROPOSAL.md` §10 for the one area (listing photos) where
the schema is correct but the API does not expose it.

---

## 13. Open items

Tracked, not answered. **Do not resolve these by guessing.**

### 13.1 Closed by the decision round

| ID | Item | Resolution |
|---|---|---|
| ~~OQ-01~~ | Transaction status transitions and who may perform each | **Partly closed by [D-15]** — states, both transitions, terminality and two-party cancellation are settled. The completion-confirmation actor remains open as **A-03 / OQ-15**. |
| ~~OQ-02~~ | Listing publication and self-publish | **Closed by [D-02]** — moderated publication, seller cannot self-publish, admin approval required. |
| ~~OQ-03~~ | The price-estimation method | **Closed as a *requirement*, not an answer.** [D-03] mandates a dedicated service and forbids inventing an algorithm; the method itself is still undocumented — see OQ-03 below. |
| ~~OQ-09~~ | Listing photo delivery | **Partly closed** — no schema change permitted, and the mobile API must expose photos ([SEC] §4.5). Upload mechanism and URL scheme remain open. |

### 13.2 Still open

| ID | Item |
|---|---|
| **DG-01** | The planning original of this document is not stored in Git. This transcription is the repository's copy. Archive the original, or confirm this file is the canonical version. |
| **OQ-03** | The **estimation method** itself. [D-03] requires a dedicated service and forbids inventing an algorithm, but no algorithm, model, or integration exists in the repository. Must be documented before the production estimator is implemented. |
| **OQ-04** | A controlled vocabulary for `livestock_type`, given it stays free text. (§4.1) |
| **OQ-06** | Which notification types exist and what triggers them. (§7) |
| **OQ-07** | Whether messaging requires a verified seller, an existing transaction, or a listing context. (§8.2) |
| **OQ-08** | Whether marketplace browsing requires an account, or is available to signed-out visitors. |
| **OQ-09** | **Listing photo representation**: upload mechanism, storage, URL scheme, and the exact mobile response shape. Now constrained: **no schema change** (§4.5). |
| **OQ-10** | Identity verification strength. `id_document_ref` is a free-text reference with no verification semantics defined. |
| **OQ-11** | Session/token lifetime policy. Tokens currently never expire. |
| **OQ-12** | Whether an **administrator account** may authenticate through the mobile flow at all, and if so which authorisation context it carries. [SEC] §10.5 settles that a mobile token is never admin-authority; it does not settle whether a `role = admin` account may hold one. |
| **OQ-14** | **Admin listing moderation endpoints.** [D-02] requires admin approval to move a listing to `active`, and admin rejection to move it to `inactive`. The Admin Web can only **read** listings today — there is no approve, reject, or deactivate route. This is a required capability with no existing implementation. |
| **OQ-16** | Listing `inactive` → `active` reactivation is not a permitted transition under [D-02]. Whether a deactivated listing can ever be re-listed — and if so whether that requires a fresh `draft` → `pending` cycle — is not stated. |
| **OQ-17** | What happens to an `active` listing when its `quantity` is exhausted by transactions. Auto-`sold`, auto-`inactive`, or left `active`? Not covered by [D-02]. |

### 13.3 Ambiguities inside approved decisions

Recorded rather than invented, per the D-15 instruction.

| ID | Ambiguity |
|---|---|
| **A-01** | [D-02] defines `draft → pending` as seller submission, but does not permit `pending → draft`. A seller whose listing is rejected to `inactive` therefore has no way to revise and resubmit the same record. Whether a rejected listing can be edited and resubmitted, or must be replaced, is not stated. |
| **A-02** | [D-02] permits `pending → inactive` and `active → inactive` but states no path back to `active`. See OQ-16. |
| **A-03** | [D-15] rule 4 requires "the appropriate transaction confirmation" without naming the actor or the event. The `complete` transition must not be implemented until this is answered. See OQ-15. |
| **OQ-15** | Who performs transaction completion confirmation, and what constitutes it — seller action, buyer action, or mutual agreement? |
| **OQ-18** | [D-02] rule 4 says a `sold` listing is "no longer available for new transactions", but does not say which transition marks it `sold`, or whether quantity-based partial sales are in scope. |

---

## 14. Change control

This document describes **approved** behaviour.

* Do not edit it to resolve a disagreement between it and the implementation.
* Do not use it to justify a feature that was not approved.
* Do not extend it without going back through approval.
* If the implementation and this document disagree, that is a defect to be
  **reported** — in the appropriate place — and not silently reconciled.

Related: `MOBILE_API_CONTRACT_PROPOSAL.md` (proposal, under review),
`../AGENTS.md`, `../DESIGN.md`, `../mobile/AGENTS.md`.
