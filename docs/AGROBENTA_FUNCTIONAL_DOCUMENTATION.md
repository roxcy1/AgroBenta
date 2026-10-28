# AgroBenta — Functional & System Documentation

**Status: APPROVED — aligned to the capstone manuscript (2026-10-24);
listing-input decisions DEC-01 to DEC-03 approved 2026-10-27**

---

## 0. Provenance and status — read this first

This document is the repository's working copy of the AgroBenta functional and
system rules.

**The capstone manuscript is the final, authoritative source.**

> *AgroBenta: A Mobile-Based Livestock Trading Application with AI-Based Price
> Suggestion, Seller Verification, and Data Analytics* — capstone project,
> Masters in Information Technology, State University of Northern Negros
> (manuscript dated 2026-10-18, referred to below as **"the manuscript"**).

On 2026-10-24 the project manager confirmed that the manuscript is the final
document. This file was rewritten to match it (see §15, Change log). The
earlier planning transcription and its explicit decision round (D-02, D-03,
D-15, SEC) are kept below **only where the manuscript agrees with them or is
silent**.

### 0.1 Source-of-truth order

1. **The manuscript** — its text (Chapters 1–3, Scope and Limitations,
   Definition of Terms, Methodology) and its prototype screens, class diagrams
   and ERD.
2. **This document** — the repository's restatement of the manuscript, plus
   earlier approved decisions the manuscript does not contradict.
3. `MOBILE_API_CONTRACT_PROPOSAL.md` — a proposal; it never overrides 1 or 2.

Where this document and the manuscript disagree, **the manuscript wins** and
this document is wrong — report it and fix it here.

Where the manuscript **contradicts itself** (for example, a prototype screen
against the text, or the class diagrams against the ERD), the point is recorded
as an open item in §13 and must be answered by the manuscript's author. It is
not settled by guessing.

Where the manuscript is **unavailable or silent**, a rule may be adopted as an
explicit project-owner decision and marked **[DEC-nn]**. Such a rule is binding
until the manuscript can be checked. If the manuscript states something
different, the manuscript wins and this document is corrected.

### 0.2 Markers used in this document

| Marker | Meaning |
|---|---|
| **[MS]** | Taken from the manuscript text. Page numbers refer to the manuscript PDF. |
| **[MS-P]** | Taken from a manuscript prototype screen (Figures 4–27). |
| **[D-nn]** / **[SEC]** | An earlier approved decision, kept because the manuscript agrees or is silent. |
| **[DEC-nn]** | A project-owner decision adopted after the 2026-10-24 alignment, where the manuscript was unavailable or silent. Not a manuscript rule; see §13.4. |
| **[OPEN]** | Not settled. Listed in §13. Do not implement a guess. |

### 0.3 Terminology

| Use | Avoid |
|---|---|
| "Become a Seller" — the action of applying for seller verification **[MS-P]** | "Register as seller", "seller account" (there is only one account) |
| "Seller Mode" / "Buyer Mode" — the two **views** of the app for a verified seller **[MS-P]** (§2.7) | "Seller account" / "buyer account" as if they were separate accounts |
| "role" / "seller capability" (`seller_capability`) | "account type" |
| "seller verification" | "seller approval request" as a user-facing term |
| "verified seller" **[MS]** | "approved account", "certified seller" |
| "AI-based price suggestion" — a reference price from an external AI service **[MS]** | Wording that claims AgroBenta trained its own AI model (§5.4) |
| "inquiry" — a structured buyer question about a listing, separate from messages **[MS]** | Using "inquiry" and "message" interchangeably |

---

## 1. Purpose and scope

AgroBenta is a mobile-based livestock trading application connecting
**buyers** and **sellers**, with **seller verification** as the trust
mechanism, an **AI-based price suggestion** as a pricing reference, and **data
analytics** for administrators. **[MS p.2–4]**

| Aspect | Rule |
|---|---|
| Locale | The Municipality of **Trinidad, Bohol**. **[MS p.3, p.13, p.96]** |
| Livestock covered | **Cattle, carabao, goats and swine** only. Other categories are outside the scope. **[MS p.13, Limitation 2]** (§4.1) |
| Target mobile platform | **Android**. **[MS Table 3]** |
| Out of scope | Payment processing, transportation or delivery services, and independent verification of payment or delivery. **[MS p.4, Limitation 5]** (§11) |

Three applications:

| Application | Stack | Responsibility |
|---|---|---|
| Backend | Laravel REST API + MySQL | All business logic, authorization, data |
| Admin Web | React | Administrator workflows |
| Mobile | Flutter | Buyer and seller workflows |

**[MS p.41, Figure 3]**

The **backend is the only place business rules are enforced.** Neither client
may implement a rule the server does not enforce.

---

## 2. Single-account model

**Every person has exactly one account. Buying and selling happen through the
same account.** **[MS p.41–42]**: *"The system supports users who act as
buyers and sellers through the same account … This approach allows users to
participate in the marketplace without requiring separate accounts for buying
and selling."*

```text
register ──> buyer                      role              = user
                │                        seller_capability = buyer
                │
                │ user chooses "Become a Seller"
                ▼
           seller verification          status = submitted
                │
           admin reviews
                ▼
             approved ──> verified       role              = user
                          seller         seller_capability = seller
                                         (may now use Seller Mode, §2.7)
```

### 2.1 Initial state

Every registered user starts as a **buyer**. This is never negotiable at
registration time.

### 2.2 Becoming a seller

The user-facing action is **"Become a Seller"** **[MS-P Figure 19]**. A buyer
may start it at any time by submitting seller verification (§3).

### 2.3 Prohibited

* A separate buyer account and a separate seller account. **[MS p.42]**
* A second login, second token or second user id for seller activity.
* Granting any selling right from the client. The app's current mode (§2.7) is
  a **display choice only**; it never grants or removes a right.

The account a user registers with is the account they transact from,
permanently.

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
| `seller` | Verified seller. Selling rights granted. |

These match the manuscript ERD (`users.role ENUM('user','admin')`,
`users.seller_capability ENUM('buyer','seller')`). **[MS p.94]**

> Note: the manuscript's Authentication class diagram (p.87) shows
> `role: user, admin, seller`. That conflicts with the ERD and with p.41–42.
> The ERD is followed here; see §13, MS-04.

### 2.5 The four valid combinations

| `role` | `seller_capability` | Meaning |
|---|---|---|
| `user` | `buyer` | Registered buyer. The default. |
| `user` | `seller` | Verified seller. |
| `admin` | `buyer` | Administrator who does not transact. |
| `admin` | `seller` | Administrator who is also a verified seller. |

Selling rights come from `seller_capability` alone; `role` is irrelevant to
them. An administrator is `role = admin`, regardless of `seller_capability`.

### 2.6 Granting seller capability

`seller_capability` becomes `seller` **only** when a seller verification is
**approved** by an administrator (§3). **[MS p.14–15, p.42]**: *"Access to
seller functions is subject to the system's verification and approval
requirements."*

**[SEC]** A user cannot become a seller by changing their own account fields:

* A registration request must not be able to set `role` or
  `seller_capability`. New accounts are always `role = user`,
  `seller_capability = buyer`.
* A profile update must not be able to set `role` or `seller_capability`.
* Neither field is ever accepted from a mobile request. See §10.

### 2.7 Account Mode — Seller Mode and Buyer Mode **[MS-P Figure 20]**

The mobile profile shows an **Account Mode** card. A verified seller can switch
between **Seller Mode** (*"You can list and manage your livestock"*) and
**Buyer Mode** (*"Browse and purchase livestock"*).

Rules:

1. **Seller Mode is available only when the server reports
   `seller_capability = seller`.** A user who is not a verified seller sees
   "Become a Seller" (or their verification status) instead.
2. **The mode is a view, not an account.** Both modes use the same account and
   the same login token. Switching sends nothing that changes `role` or
   `seller_capability`.
3. **The server never trusts the mode.** Every seller action is authorised by
   the server from `seller_capability`, exactly as if no mode existed.
4. Seller Mode shows the seller's surfaces (seller dashboard, My Listings,
   received inquiries, seller-side transactions) **[MS-P Figures 21, 23, 25,
   26]**. Buyer Mode shows the marketplace and the user's own purchases.
5. A verified seller remains able to buy. Buyer Mode is available to every
   account.
6. The selected mode is a per-user preference. It must be cleared on logout so
   a different account never inherits it.

### 2.8 Sign-in and account features **[MS p.5, p.13; MS-P Figures 4–5]**

| Feature | Status |
|---|---|
| Registration with email and password | In scope. |
| Login with email and password | In scope. |
| Profile management (view and update personal details, change password) | In scope. **[MS-P Figure 20: Personal Information, Address, Change Password, Notification Settings]** |
| **Forgot password** | Shown on the login prototype. In scope; the recovery method is **[OPEN]** (§13, MS-10). |
| "Remember me" | Shown on the login prototype. **[OPEN]** (§13, MS-11). |
| Google / Facebook sign-in | Shown on the login prototype. **[OPEN]** (§13, MS-11). |

---

## 3. Seller verification

**[MS p.5, p.14, p.18, p.20, p.42; MS-P Figure 19]** A user who intends to sell
submits their information and supporting documents. An administrator reviews
the submission through the Admin Web and approves or rejects it.

### 3.1 States

Exactly four. These match the manuscript ERD. **[MS p.94]**

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

* A user may hold **multiple** verification records over time.
* Each submission is a **new row**. An existing record is never updated back to
  `submitted`, and a rejected record's history is never overwritten.
* A new submission is permitted **only** when the user's most recent
  verification is `rejected`. A user with an open verification cannot submit
  again.
* The user's current verification state is their **most recent** record.
* `seller_capability` is derived from the most recent record.

> The prototype's "Edit Application" button on a pending application
> (Figure 19, last screen) is **[OPEN]** — see §13, MS-06.

### 3.3 What verification carries **[MS-P Figure 19]**

**Basic information**

| Field | Required | Notes |
|---|---|---|
| Full name | yes | Prefilled from the account. |
| Phone number | yes | |
| Address | yes | Within the locale (§1). |
| Farm / business name | **no** — shown as optional in the prototype | The current backend requires `business_name`; see §13, MS-05. |
| Business description | no | Existing field. |
| `id_document_ref` | no | Existing free-text reference field. Not shown in the prototype. |

**Supporting documents** — uploaded files, reviewed by an administrator:

| Document | Required | Notes |
|---|---|---|
| **Valid ID** | yes | Government-issued (e.g. Philippine National ID, Driver's License, Passport). |
| **Proof of Address** | yes | e.g. utility bill, barangay certificate. |
| **Farm photos** | no | Photos of the seller's livestock or farm area. |

The manuscript does **not** include a selfie. The current implementation
collects an ID document and a selfie; see §13, MS-05.

**Handling of documents [SEC]:**

* Stored on **private** storage, never at a public URL.
* Readable only by the applicant (their own documents) and by administrators.
* Never included in any marketplace or other-user response.
* Retention and deletion (for example after rejection) are **[OPEN]**,
  §13, MS-07. The manuscript commits to handling personal data responsibly and
  collecting only what the system needs **[MS p.102, p.104]**.

| Field | Notes |
|---|---|
| `admin_note` | Written by the administrator. Shown to the user on `rejected`. |

### 3.4 What a verified status means **[MS Limitation 6]**

A verified status records the outcome of the platform's review. It **does not**
guarantee livestock ownership, animal health, livestock quality, the accuracy
of every seller statement, or the completion of a transaction. User-facing
text must not imply otherwise.

---

## 4. Livestock listings

The marketplace inventory unit. Owned by exactly one seller.

| Aspect | Rule |
|---|---|
| Ownership | Exactly one seller per listing. |
| Ownership assignment | Set by the server from the authenticated user. **Never accepted from the client.** |
| Status | `draft`, `pending`, `active`, `sold`, `inactive`. **[MS ERD p.94]** |
| Default status | `draft`. |
| Category | `livestock_type`: **cattle, carabao, goat, swine** (§4.1). |
| Title | Shown as required in the prototype **[MS-P Figure 22]**; there is no title column in the ERD — see §13, MS-08. |
| Description | Required in the prototype (up to 500 characters). |
| Price | `asking_price`, set by the seller; at most two decimal places **[DEC-02]** (§4.7). |
| Quantity | Whole units, at least 1. |
| Breed | Optional. |
| Age | `age_value` + `age_unit` (`day` / `month` / `year`). Optional; maximum 25 years / 300 months / 9,125 days according to the selected unit **[DEC-01]** (§4.7). |
| Weight | `weight_value` + `weight_unit` (`kg` / `lb`). Optional; at most two decimal places **[DEC-02]** (§4.7). |
| Sex | `gender`: `male` / `female`. Optional. |
| Condition | `health_status`, free text. Optional. |
| Vaccination | `vaccination`, free text. Optional. |
| Location | Required. Within the locale (§1). |
| Photos | At least one photo **[MS-P Figure 22]**, required at submission **[DEC-03]**. A draft may have none (§4.5). Stored in `listings.photos` (JSON). |

Listing information follows **[MS p.14]**: *"livestock category, breed, age,
sex, weight, condition, location, images, description, and asking price."*

### 4.1 Livestock categories **[MS p.13, Limitation 2]**

The initial implementation covers exactly **cattle, carabao, goats and swine**.
`livestock_type` must be one of these four.

* Enforce this in request validation and offer the four as choices in the
  mobile form. A schema change is not required.
* The prototype's "Others" option and the "Native Chicken" sample listing are
  outside the written scope — see §13, MS-03.

### 4.2 Only verified sellers may create listings

Creating or managing a listing requires `seller_capability = seller`.
**[MS p.14]**: *"Allows approved sellers to create, update, manage, and remove
their livestock listings."*

### 4.3 Price is the seller's decision

`asking_price` is set by the seller. The AI price suggestion (§5) informs that
decision and never sets it. **[MS Limitation 4]**

### 4.4 Publication lifecycle **[D-02]**

```text
  DRAFT ──submit──> PENDING ──admin approve──> ACTIVE ──seller marks sold──> SOLD
                      │                          │
                      └──admin reject──> INACTIVE<┘ admin deactivates
```

| From | To | Who |
|---|---|---|
| `draft` | `pending` | Seller submits for review |
| `pending` | `active` | Admin approves |
| `pending` | `inactive` | Admin rejects |
| `active` | `inactive` | Admin deactivates |
| `active` | `sold` | **Seller marks as sold** **[MS-P Figure 23]** |

Rules:

1. Draft listings are private to the seller.
2. Pending listings are not visible in the buyer marketplace.
3. Active listings are visible in the buyer marketplace.
4. Sold listings are no longer available for new transactions; the seller can
   still view them under "Sold" **[MS-P Figure 23]**.
5. Inactive listings are not publicly available.
6. Buyers browse only `active` listings. The marketplace query filters to
   `active` server-side.
7. A seller never sends `status` directly. The server sets it from the action.
8. A listing must have at least one stored photo before it can be submitted for
   review, and therefore before it can become `active` (§4.5). **[DEC-03]**

> **[OPEN] MS-01 — direct publish vs admin approval.** The Add New Listing
> prototype (Figure 22) has a seller-chosen "Status: Active" and a "Publish
> Listing" button, which suggests a seller can publish directly. The Livestock
> Listing class diagram (p.88) gives the administrator `approveListing` and
> `rejectListing`. Until the author decides, the admin-approval lifecycle above
> stays in force.

> **[OPEN] MS-02 — reactivation.** The prototype shows "Reactivate Listing" on
> a sold listing (Figure 23). No transition back to `active` is defined above
> until this is decided.

**Do not invent additional listing states.** The five above are the complete
set and match the ERD.

### 4.5 Listing photos

* `listings.photos` is stored as JSON and holds filenames; the API returns
  absolute URLs.
* At least one photo is required to publish **[MS-P Figure 22]**; the maximum is
  a platform setting.
* A draft may have no photos. The seller must have at least one stored photo
  before **submitting for review**; submission is refused otherwise. **[DEC-03]**
* Admin approval must also refuse a `pending` listing with no stored photo. This
  is a guard for a listing that reached `pending` before the submission rule
  existed; for new submissions the submit check is the enforcement point.
  **[DEC-03]**
* Photos are public once the listing is active.

### 4.6 Search and filtering **[MS p.14; MS-P Figures 7–8]**

Users can search and filter active listings by livestock category, location,
asking price and other available listing characteristics.

### 4.7 Numeric limits **[DEC-01, DEC-02]**

* **Age.** When an age is given, the maximum depends on the selected unit:
  **25 years**, **300 months**, or **9,125 days**. The limit is applied in the
  unit the seller selected; the server does not convert one unit into another.
* **Weight and asking price.** At most **two decimal places**. A value with three
  or more decimal places is rejected, not rounded, so the stored amount always
  matches what the seller entered.
* Both limits are enforced by the API and in the mobile form; the API is
  authoritative.

These are project-owner decisions, not manuscript rules. The final manuscript
was not available when they were adopted, and the draft available at the time
did not state them. Re-check them against the manuscript when it is available
(§0.1).

---

## 5. AI-based price suggestion

### 5.1 Purpose **[MS p.14, p.48]**

An estimated price or price range for a livestock listing, used **as a
reference**: for sellers when setting their asking price, and for buyers when
evaluating listings. **[MS p.48]**

### 5.2 The seller decides **[MS Limitation 4; D-03]**

> The suggestion is a reference only. **The seller determines the final asking
> price.**

* The suggestion never writes, overwrites or defaults `asking_price`.
* A seller may accept, adjust or ignore a suggestion, and may list without ever
  requesting one. "Use suggested price" only pre-fills the editable price field
  **[MS-P Figure 24]**.
* A suggestion is not a valuation, a guarantee, a verified selling price or a
  mandatory asking price.
* The screen must say, as the prototype does, that the suggestion is a
  reference only and the seller can still set their own selling price.

### 5.3 How it works — external AI API **[MS p.17, p.42, p.48–51]**

```text
Livestock information → Laravel backend → External AI API
                     → Response validation → Price suggestion display
```

1. The seller provides the livestock details. Inputs may include livestock
   type, breed, age, sex, weight, condition and location, as required by the
   selected service.
2. **The mobile app talks only to the Laravel backend.** The backend prepares
   and sends the request to the external service and holds its credentials.
3. The backend validates the response. Only a valid estimate in the expected
   format is shown.
4. If the service is unavailable, fails, or returns an invalid response, the
   app shows a clear message that a suggestion cannot currently be generated.
   **It never shows a made-up or placeholder number.**

The external provider, request format, required fields, response format and
error handling are **[OPEN]** until the provider is chosen and tested
(§13, MS-09). They must be documented once confirmed.

### 5.4 Constraints **[MS Limitation 3; D-03]**

1. The estimation is implemented as a dedicated backend service, not inline
   controller logic and not a model method.
2. **AgroBenta does not train its own AI model.** No code, comment, commit
   message, screen or document may claim that it does. **[MS p.17]**: *"AgroBenta
   will not be described as independently training an AI model when price
   estimation is performed by the external service."*
3. The output is a range (minimum and maximum) and/or a suggested value, with
   a basis or explanation where the service provides one.
4. The feature may not be described as fully operational until it has been
   integrated and tested. **[MS p.46, p.51]**

> The Definition of Terms (p.20) describes the feature as using "an artificial
> intelligence or machine-learning model … and available historical pricing
> data". That conflicts with Limitation 3. This document follows Limitation 3;
> see §13, MS-09.

### 5.5 Stored data

| Field | Meaning |
|---|---|
| `estimated_min` / `estimated_max` | The suggested range. |
| `estimated_value` | Suggested / reference value within the range. |
| `basis` | How the estimate was derived, as returned or summarised. |
| `input_snapshot` | The inputs sent, captured at request time. |
| `estimated_at` | When the estimate was produced. |

One listing may have many estimates (`ai_price_estimates`). **[MS ERD p.94]**

---

## 6. Transactions

**[MS p.5, p.15, Limitation 5; MS-P Figures 13–18, 26]** A transaction records
an agreed livestock sale between a buyer and a seller and its status.

| Aspect | Rule |
|---|---|
| Parties | Exactly one `buyer_id` and one `seller_id`, both `users`. |
| Listing | Exactly one `listing_id`. |
| Quantity | Whole units. |
| Amount | `total_amount`, computed by the server. |
| Status | `pending`, `completed`, `cancelled` (ERD). See §6.4 for the full flow. |

### 6.1 Amount is server-computed

`total_amount` is derived by the server. A client-supplied amount is never
trusted or stored. Whether an agreed price different from the asking price is
supported is **[OPEN]**, §13, MS-13.

### 6.2 Self-transaction

A user cannot be both buyer and seller on the same transaction.

### 6.3 No payment processing, no transport service **[MS p.4, Limitation 5]**

AgroBenta does not process payments and does not provide transportation or
delivery. Buyers and sellers negotiate, arrange payment and transport, and
complete the sale themselves. The system may **record** information users
supply (for example "Cash (in person)", "Paper receipt" **[MS-P Figure 26]**),
but these records do not prove that payment or delivery happened. User-facing
text must say so (as in the prototype: *"Payment and receipt are handled
directly between buyer and seller."*).

### 6.4 Flow **[MS-P Figures 13–18, 26]**

```text
 1. Purchase request submitted     (buyer)
 2. Seller accepts                 (seller)
 3. Livestock delivered / picked up (arranged by the parties, outside the app)
 4. Buyer confirms receipt         (buyer)   ──> COMPLETED
       any point before 4 ──cancel──> CANCELLED
```

Rules:

1. **The buyer initiates a transaction** by sending a purchase request on an
   active listing. A seller does not create transactions.
2. A new transaction starts as `pending` and awaits the seller.
3. **The seller accepts** the request.
4. **The buyer confirms receipt** of the livestock. This completes the
   transaction. *(Closes the earlier open question A-03 / OQ-15.)*
5. `completed` and `cancelled` are terminal.
6. A seller sees and manages only transactions on their own listings; scoping
   is by `transactions.seller_id`, derived from the listing.
7. Both parties may cancel while the transaction is not yet completed. The
   exact cut-off is **[OPEN]**, §13, MS-14.

> **[OPEN] MS-12 — intermediate statuses.** The prototype shows "Pending Seller
> Confirmation", "Seller Accepted", "In Delivery"/"On the way", and seller tabs
> "Inquiry", "Negotiating", "Confirmed", "In Delivery", "Completed". The ERD
> only has `pending`, `completed`, `cancelled`. How "seller accepted" and "in
> delivery" are stored needs a decision before implementation.

> **[OPEN] MS-13 — delivery fee and agreed price.** The prototype shows
> "Agreed Price", "Reference Price", "Delivery Fee" and "Total Amount". Whether
> these are recorded, and whether they conflict with Limitation 5, needs a
> decision.

### 6.5 Nothing after completion

There is no refund, reversal, payout, shipment tracking or dispute state. A
completed transaction is a record of an agreed sale and nothing more.

---

## 7. Notifications

**[MS p.15; MS-P Figure 27]** System-generated messages for a user.

| Aspect | Rule |
|---|---|
| Identity | A UUID. |
| Owner | Exactly one notifiable user. |
| Read state | `read_at`; `null` means unread. |
| Content | A JSON payload plus a type. |

Events that notify (from the manuscript):

* Seller verification updates (approved / rejected).
* Transaction-related status changes.

Notifications for new inquiries, new messages and listing approval/rejection
fit the same pattern; the full list and whether phone push notifications are
used are **[OPEN]**, §13, MS-15.

A user may only read or act on **their own** notifications.

---

## 8. Communication and inquiries **[MS p.5, p.15]**

> *"Allows interested buyers and sellers to communicate about livestock
> listings and potential purchases. Inquiries will be recorded separately from
> ordinary messages and from agreed transaction records."* **[MS p.15]**

### 8.1 Messages **[MS-P Figure 12]**

| Aspect | Rule |
|---|---|
| Parties | Exactly one `sender_id` and one `receiver_id`. |
| Listing context | Optional. |
| Read state | `read_at`; `null` means unread. |
| Content | Plain text. |

There is **no conversation table**. A conversation is derived from the
messages between two users (and optionally a listing). This matches the ERD.
**[MS p.94]** (The Messaging class diagram on p.89 shows a `Conversation`
model; the ERD is followed — §13, MS-04.)

A user may read and send messages only where they are the sender or the
receiver.

### 8.2 Inquiries **[MS-P Figures 10, 11, 25]**

An inquiry is a structured question from a buyer about a specific listing. It
is stored separately from messages and from transactions.

**The buyer sends** (Figure 10):

| Field | Required |
|---|---|
| Subject | yes |
| Message (up to 500 characters) | yes |
| Interested in purchasing? (yes / no) | yes |
| Preferred transaction method: direct deal / arrange delivery | yes |
| Delivery method and delivery fee | when relevant — see §13, MS-13 |
| Preferred contact method (in-app message) | yes |
| Preferred schedule | no |

**The seller views and responds** (Figure 25): availability (available / not
available), a written response, an optional suggested price, and a delivery
arrangement. The seller may also decline the inquiry.

Rules:

1. The buyer is the authenticated user; the seller is derived from the
   listing. Neither is accepted from the request.
2. A seller sees only inquiries about their own listings.
3. Sending an inquiry does not change the listing, create a transaction or
   reserve stock.
4. Administrators may view inquiries for monitoring.

### 8.3 Eligibility

Whether messaging requires a listing context, and who may message whom, is
**[OPEN]**, §13, OQ-07.

---

## 9. Admin Web vs Mobile responsibilities

### 9.1 There is no admin mobile application

**[MS p.15–16]** The administrator interface is the React web dashboard only.

### 9.2 Division

| Concern | Owner |
|---|---|
| Seller verification **review** (approve / reject) | Admin Web |
| Seller verification **submission** | Mobile |
| User management | Admin Web |
| Listing monitoring (and moderation, §4.4) | Admin Web |
| Transaction monitoring | Admin Web |
| Inquiry monitoring | Admin Web |
| Activity monitoring | Admin Web |
| Data analytics and reports | Admin Web |
| Platform settings | Admin Web |
| Marketplace browsing, search and filtering | Mobile |
| Listing creation and management | Mobile (verified sellers) |
| AI price suggestion | Mobile (sellers; buyers see the reference, §5.1) |
| Inquiries (send and respond) | Mobile |
| Messages | Mobile |
| Transactions | Mobile (both parties) |
| Notifications | Mobile |
| Own profile and Account Mode | Mobile |

**[MS p.15–16; MS-P admin screens, p.83–86]**

### 9.3 The boundary is a security boundary

* The mobile app must not call admin endpoints.
* An admin token must never authorise a mobile request, and a mobile token must
  never authorise an admin request.
* Whether an administrator account may sign in to the mobile app is
  **[OPEN]**, §13, OQ-12.

### 9.4 Data analytics **[MS p.6, Limitation 7]**

The analytics module summarises records stored in AgroBenta — listings,
verification statuses, transactions, livestock categories and pricing
information. Reports describe **recorded AgroBenta activity only**, not the
whole livestock market of Trinidad, Bohol. Amounts must not be labelled as
revenue or payments (§6.3).

---

## 10. Security requirements **[SEC]**

These apply to every write endpoint.

### 10.1 Authorization-sensitive fields are never client-controlled

| Field | Must be derived from |
|---|---|
| `users.role` | Never client-set. |
| `users.seller_capability` | The approved verification workflow (§2.6, §3). |
| `listings.seller_id` | The authenticated user. |
| `listings.status` | The server, from the action taken (§4.4). |
| `transactions.buyer_id` | The authenticated user. |
| `transactions.seller_id` | `listing.seller_id`. |
| `transactions.total_amount` | The server (§6.1). |
| `messages.sender_id` | The authenticated user. |
| Inquiry buyer / seller | The authenticated user / `listing.seller_id`. |

### 10.2 Explicit request field allow-lists

* A dedicated Form Request per endpoint, permitting only the documented
  client-settable fields.
* Never pass a request body straight into a mass-assignment call.
* Adding a field to a model must never silently make it client-settable.

### 10.3 Derived, not declared

Identity and ownership come from the session and from relationships, never
from the request body. A path parameter is a selector, not proof of ownership.

### 10.4 Response separation

* Mobile responses use mobile-specific resources, not the admin ones.
* Public marketplace responses never expose a seller's private email address.
* A mobile response never contains administrator-only data: reviewer
  identities, internal notes, another user's verification documents.
* Counterparty contact details appear only inside a transaction or inquiry the
  viewer is a party to.

### 10.5 Authentication separation

* Mobile authentication is separate from Admin Web authentication.
* Mobile users never receive an admin-authority token.

### 10.6 Personal data **[MS p.101–104]**

Only the information needed for the system's functions is collected. Personal
data and verification documents are protected against unauthorised access and
disclosure (§3.3).

---

## 11. Out of scope

| Excluded | Source |
|---|---|
| **Payment processing** (capture, settlement, refunds) | **[MS p.4, Limitation 5]** |
| **Transportation / delivery service** (the app does not transport or track livestock) | **[MS p.4, Limitation 5]** |
| Independent proof of payment or delivery | **[MS Limitation 5]** |
| Livestock categories other than cattle, carabao, goats, swine | **[MS Limitation 2]** |
| Training an in-house AI model | **[MS Limitation 3]** |
| Locales other than Trinidad, Bohol (initial implementation) | **[MS Limitation 1]** |
| A separate admin mobile application | §9.1 |
| A stored conversation table | §8.1, ERD |
| A currency column (amounts are in Philippine pesos, ₱) | ERD; **[MS-P]** |

---

## 12. Data design

The manuscript ERD (p.94) is the reference schema:

| Table | Purpose | Key relationships |
|---|---|---|
| `users` | All accounts | `role`, `seller_capability` |
| `seller_verifications` | Verification submissions and history | many per `user` (§3.2) |
| `listings` | Marketplace inventory | one `seller_id` |
| `ai_price_estimates` | Price suggestion history | many per `listing` |
| `transactions` | Agreed sales | one `buyer_id`, one `seller_id`, one `listing_id` |
| `messages` | Direct messages | `sender_id`, `receiver_id`, optional `listing_id` |
| `notifications` | Per-user notifications | one notifiable; UUID identity |
| `activities` | System activity log | one optional `user_id` |
| `settings` | Platform settings | keyed |
| `personal_access_tokens`, `sessions`, `password_reset_tokens` | Framework tables | — |

### 12.1 Required by the manuscript text but not drawn in the ERD

| Data | Source | Note |
|---|---|---|
| **Inquiries** | **[MS p.15]** "recorded separately" | Stored in its own table. Add it to the manuscript ERD. |
| **Verification documents** | **[MS p.14, p.20]** "supporting documents" | Stored privately (§3.3). Add to the manuscript ERD. |
| Listing title | **[MS-P Figure 22]** | See §13, MS-08. |

### 12.2 Constraints on change

* Do **not** add a conversation table (§8.1).
* Do **not** add a sixth listing state (§4.4).
* Do **not** make `seller_verifications.user_id` unique — it is one-to-many
  (§3.2).
* Do **not** add a second account table or split buyers and sellers (§2.3).
* Do **not** add payment-processing tables (§11).
* Do **not** add a listing `title` column while MS-08 is open (§12.1, §13.2).
* Preserve backward compatibility; existing data must remain readable.

### 12.3 Manuscript diagrams that conflict with the ERD

The class diagrams (p.86–93) show elements that are not in the ERD and are not
part of this design: a `Payment` model and `confirmPayment()`, a `Conversation`
model, a `JwtService` (the system uses Laravel Sanctum tokens), `role: seller`,
a listing status `archived`, and `AISuggestionFactor` / `modelVersion`. These
follow the ERD and the manuscript text above, not the class diagrams — see
§13, MS-04.

---

## 13. Open items

Not settled. **Do not resolve these by guessing.** Questions marked **MS-** are
for the manuscript's author.

### 13.1 Closed by aligning to the manuscript

| ID | Item | Resolution |
|---|---|---|
| ~~DG-01~~ | The planning original was not in Git | The manuscript is the final document (§0). |
| ~~OQ-03~~ | Estimation method | An **external AI API** through the backend (§5.3). The provider is still open (MS-09). |
| ~~OQ-04~~ | Controlled vocabulary for `livestock_type` | **Cattle, carabao, goat, swine** (§4.1). |
| ~~OQ-06~~ | Notification types (partly) | Verification updates and transaction status changes (§7). The full list is MS-15. |
| ~~OQ-15 / A-03~~ | Who confirms completion | **Seller accepts, buyer confirms receipt** (§6.4). |
| ~~D-13~~ | Can buyers see a price suggestion? | **Yes**, as a reference **[MS p.48]** (§5.1). |
| ~~Former §2.3 "no mode switch"~~ | Seller Mode / Buyer Mode | Allowed as a view switch for verified sellers (§2.7). |
| ~~Former §3.3 "no document upload"~~ | Identity documents | Supporting documents are uploaded and stored privately (§3.3). |
| ~~Former §11 "no inquiries entity"~~ | Inquiries | Kept separate from messages and transactions (§8.2). |

### 13.2 Questions for the manuscript's author

| ID | Question |
|---|---|
| **MS-01** | **Listing publication:** may a seller publish directly (prototype Figure 22, "Status: Active" / "Publish Listing"), or must an administrator approve first (class diagram p.88)? |
| **MS-02** | **Reactivation:** may a sold or inactive listing be put back on sale ("Reactivate Listing", Figure 23)? |
| **MS-03** | **Categories:** the prototype shows "Others", "Pig" and a "Native Chicken" sample, and omits carabao. Are only cattle, carabao, goats and swine allowed? |
| **MS-04** | **Diagrams:** will the class diagrams (Payment, Conversation, JWT, `role: seller`, `archived`) be redrawn to match the ERD and the text? |
| **MS-05** | **Verification documents:** confirm Valid ID + Proof of Address + Farm Photos (optional). Should the selfie the current app asks for be removed? Is the farm/business name optional? |
| **MS-06** | **Editing an application:** may a pending application be edited ("Edit Application", Figure 19), given that resubmission creates a new record? |
| **MS-07** | **Document retention:** who may view IDs, and when are they deleted (for example after rejection)? |
| **MS-08** | **Listing title:** the prototype requires a title; the ERD has none. Add a title field, or derive it (e.g. type + breed)? |
| **MS-09** | **AI service:** which external provider, who pays, who holds the key? Correct the Definition of Terms (p.20) to say "external AI service" rather than an in-house model. |
| **MS-10** | **Forgot password:** email code or email link? Which email service? |
| **MS-11** | **Remember me and Google/Facebook sign-in:** build them or remove them from the prototype? |
| **MS-12** | **Transaction statuses:** how are "seller accepted" and "in delivery" stored, given the ERD has only `pending`, `completed`, `cancelled`? Do the seller tabs "Inquiry" and "Negotiating" belong to transactions or to inquiries? |
| **MS-13** | **Agreed price and delivery fee:** can the agreed price differ from the asking price? Is a delivery fee recorded and added to the total, given Limitation 5? |
| **MS-14** | **Cancellation:** who may cancel, and up to which step? |
| **MS-15** | **Notifications:** the full list of events, and whether phone push notifications are required. |
| **MS-16** | **"Verified Buyer"** appears in the seller transaction prototype (Figure 26). Is there a buyer verification, or is this label a mistake? |
| **MS-17** | **Hosting for evaluation:** where will the system run for the 15 evaluators, and how will they install the app? |

### 13.3 Still open from the earlier planning round

| ID | Item |
|---|---|
| **OQ-07** | Whether messaging requires a listing context, and who may message whom. |
| **OQ-08** | Whether browsing requires an account. |
| **OQ-10** | Identity verification strength beyond administrator review. |
| **OQ-11** | Session / token lifetime. Tokens currently never expire. |
| **OQ-12** | Whether an administrator account may sign in to the mobile app. |
| **OQ-17** | What happens to an `active` listing when its quantity is used up by transactions. |
| **A-01** | Whether a rejected listing can be edited and resubmitted, or must be replaced. |

### 13.4 Closed by project-owner decision (2026-10-27)

Adopted after the 2026-10-24 manuscript alignment. The final manuscript was not
available during that review, so these are recorded as decisions, not as
manuscript rules, and must be re-checked against the manuscript when it is
available (§0.1).

| ID | Item | Resolution |
|---|---|---|
| **DEC-01** | Maximum age | 25 years / 300 months / 9,125 days, applied in the selected unit (§4.7). |
| **DEC-02** | Decimal precision | Weight and asking price accept at most two decimal places; a third decimal is rejected (§4.7). |
| **DEC-03** | Listing photos | A draft may have none; submission requires at least one stored photo, and admin approval refuses a zero-photo `pending` listing as a legacy guard (§4.4 rule 8, §4.5). |

MS-08 (listing title) remains open in §13.2. No title field or column is added.

---

## 14. Change control

* **The manuscript is authoritative.** When it changes, update this document to
  match and add a §15 entry.
* Do not use this document to justify a feature that is not in the manuscript.
* If the implementation and this document disagree, that is a defect to be
  **reported** and fixed — not silently reconciled.
* Where the manuscript contradicts itself, record it in §13 and ask the author.

Related: the manuscript (PDF, kept outside the repository),
`MOBILE_API_CONTRACT_PROPOSAL.md` (proposal), `../AGENTS.md`, `../DESIGN.md`,
`../mobile/AGENTS.md`.

---

## 15. Change log

| Date | Change |
|---|---|
| 2026-10-24 | Aligned to the capstone manuscript, confirmed by the project manager as the final document. Allowed the Seller Mode / Buyer Mode view switch (§2.7); added sign-in features (§2.8); replaced "no identity document upload" with private supporting documents (§3.3); limited livestock categories to cattle, carabao, goats and swine (§4.1); added "seller marks as sold" (§4.4); set the price suggestion to an external AI API, visible to buyers as a reference (§5); set the transaction flow to seller-accepts / buyer-confirms-receipt (§6.4); added inquiries separate from messages (§8.2); added analytics scope (§9.4); rewrote out-of-scope (§11) and open items (§13). Conflicts inside the manuscript recorded as MS-01 to MS-17. |
| 2026-10-27 | Adopted project-owner decisions DEC-01 to DEC-03: unit-aware maximum age (25 years / 300 months / 9,125 days), at most two decimal places for weight and asking price, and the photo minimum at submission with an approval-time guard for legacy listings (§4.4, §4.5, §4.7, §13.4). Added the `[DEC-nn]` marker because the manuscript was unavailable; the rules must be re-checked against it. MS-08 (listing title) remains open. |
| Earlier | Planning transcription with decision round D-02, D-03, D-15 and SEC. |
