# AgroBenta Mobile — Inquire About Livestock Screen Design

## 1. Purpose

This document defines the UI and interaction requirements for the **Inquire About Livestock** screen in the AgroBenta Flutter mobile application. The supplied screenshot is the visual reference for layout, hierarchy, spacing, color, and control styling. This document describes the intended interface; it does **not** establish that every field is currently supported by the backend.

## 2. Implementation Principles

- Follow the existing root `AGENTS.md`, root `DESIGN.md`, `mobile/AGENTS.md`, and `mobile/DESIGN.md`.
- Reuse existing themes, shared widgets, navigation, authentication, API clients, models, and error-handling patterns.
- Preserve existing backend contracts, listing lifecycle rules, authorization, and uncommitted changes.
- Do not invent endpoints, request fields, database columns, migrations, transaction states, or success responses.
- Do not use hardcoded sample livestock, seller details, prices, locations, images, or attributes in production.
- Do not stage, commit, or push changes.
- Do not reset the database, delete Docker volumes, or run destructive cleanup commands.

## 3. Screen Structure

### 3.1 App Bar

- Green app bar consistent with AgroBenta's existing mobile theme.
- Back arrow on the left.
- Centered title: **Inquire About Livestock**.
- Respect system status-bar and safe-area insets.

### 3.2 Livestock Summary Card

Show the selected listing's real data:
- Listing photo, only if a valid supported image URL or local asset is available.
- Livestock/listing title.
- Asking price in Philippine pesos (₱).
- Seller name, from the listing's existing `seller` projection (`MobileSellerResource`: `id` and `name` only).
- Location.
- Category and other attributes only when supplied by the real listing data.

Requirements:
- Preserve the actual listing ID throughout the workflow.
- Populate the card from the listing selected on the previous screen.
- Show the seller name from the listing already in hand; do not add an endpoint or a response field for it.
- Preserve image proportions and show an appropriate placeholder/error state when no usable image is available.
- Do not fabricate photo URLs or infer missing listing attributes.
- Treat the asking price as reference-only, not as a confirmed transaction price.

### 3.3 Additional Message

- Section title: **Additional Message**.
- Label: **Message \\***.
- Multiline text input, four to six visible lines, required, maximum 500 characters.
- Show a live character counter in `currentLength/500` format, starting at `0/500`.
- Placeholder: `Type your inquiry here...`
- Helper text: `Ask about availability, additional photos, or the asking price.`
- Reject empty and whitespace-only messages with a clear validation message.
- Preserve entered text after failed submission.

#### Message Templates

Under **Message templates**, offer four starter messages:

1. **Check availability** — `Hello! Is this livestock still available?`
2. **Discuss the price** — `Hello! I'm interested in this livestock. Is the price negotiable?`
3. **Visit the farm** — `Hello! Can I visit your farm to inspect this livestock?`
4. **Payment and pickup** — `Hello! I'm interested in this livestock. Can we discuss payment and collection arrangements?`

Behavior:
- Selecting a template replaces the field contents with that exact message and updates the counter.
- Selecting a template never submits the inquiry.
- The filled text remains fully editable, and the buyer may replace it with a custom message.
- A template that supplies text clears a stale required-message error.

### 3.4 Preferred Payment Method

Present four selectable cards:
1. **Cash** — “Pay with cash.”
2. **GCash** — “Pay with GCash.”
3. **Maya** — “Pay with Maya.”
4. **Other / Discuss with seller** — “Agree payment with the seller.”

Visual behavior:
- Two cards side by side when space permits.
- Green border and subtle green-tinted background for the selected card.
- Neutral border and background for unselected cards.
- Use existing project icons, not emoji or arbitrary Unicode glyphs.
- Provide accessible selection semantics and a clear selected state.

Business behavior:
- Treat the selection as the buyer's preference only.
- It must not create or confirm a transaction, payment, or seller agreement; AgroBenta does not process payments.
- The selection is required: the buyer must choose one before sending, and the server rejects an inquiry without it.
- Store the chosen value in `inquiries.payment_method` through the verified contract.

### 3.5 Preferred Livestock Collection

Present three selectable cards:
1. **Farm Pickup** — “Pick up from the seller's farm.”
2. **Arrange Transport** — “Arrange my own livestock transportation.”
3. **Discuss** — “Discuss arrangements with the seller.”

Business behavior:
- Treat the selection as the buyer's preference only.
- It must not book transportation, dispatch a rider, or imply that AgroBenta provides delivery or tracking.
- The selection is required: the buyer must choose one before sending, and the server rejects an inquiry without it.
- Store the chosen value in `inquiries.collection_method` through the verified contract.

### 3.6 Bottom Actions

Buttons:
- **Cancel** — outlined green button.
- **Send Inquiry** — filled green primary button.
- Helper text below the actions: `The seller will reply through AgroBenta messages.`

Cancel behavior:
- Navigate back to the previous screen.
- Use the existing unsaved-changes confirmation pattern if applicable.
- Never submit data when cancelling.

Send Inquiry behavior:
- Check for an existing inquiry for this buyer and listing before showing the form.
  If one exists in any status, show **Inquiry Already Sent** with **Go to Messages**
  and **Back to Browse** instead of the form.
- Validate the required message, including the 500-character ceiling and whitespace-only rejection.
- Require both the preferred payment method and the preferred collection method, with an inline error beside each section when missing.
- Prevent repeated taps while a request is in progress.
- Display a loading state during submission.
- Use the existing authenticated API client and real backend contract.
- Send only the supported fields: `listing_id`, `message`, `payment_method`, and `collection_method`.
- Show success only after the server confirms successful persistence.
- Show useful validation, authorization, network, timeout, and server errors.
- Preserve form input on failed submission.
- Do not fabricate success or silently discard unsupported fields.

The obsolete Subject, purchase-interest, Transaction Method, Delivery Details, delivery fee, contact method and schedule controls are not part of the approved screen and are not sent. If a future requirement needs one, verify the backend contract first rather than re-adding the control.

## 4. Visual Design Guidance

Follow the screenshot while remaining consistent with AgroBenta:
- Primary green app bar and primary action button.
- White or near-white page background.
- White cards with light neutral borders and softly rounded corners.
- Dark, readable labels and headings.
- Muted grey supporting text and input hints.
- Green selected states and subtle green accents.
- Comfortable spacing between sections and controls.
- Clearly distinguish required fields from optional fields.
- Reuse the existing typography scale and theme.
- Use the existing icon package.
- Avoid fixed-height layouts that overflow on smaller screens.
- Keep the form scrollable and ensure actions are reachable when the keyboard is visible.
- Respect safe areas and bottom navigation insets.
- Match the screenshot's visual hierarchy without copying its example listing values.

## 5. Navigation

- Open this screen from the selected listing's existing details screen or supported inquiry entry point.
- Pass the real listing model or stable listing identifier.
- Preserve listing context when the user cancels or returns.
- Reuse the existing navigation shell; do not create duplicate navigation bars or nested shells.
- Bottom navigation order, where implemented by the application: Home, Browse, Messages, Transactions, Profile.
- Do not create fake Messages or Transactions functionality to make navigation appear complete.

## 6. Data, Security, and Business Rules

- The user must be authenticated to submit an inquiry.
- Derive the current user from the authenticated token/session; never trust a client-supplied user ID.
- Validate listing eligibility using actual backend rules.
- Do not expose seller-private fields.
- Follow existing API authorization and response conventions.
- Listing prices are reference-only; the seller remains responsible for the final asking price.
- An inquiry is not a confirmed sale.
- Sending an inquiry must not mark a listing as sold or change its lifecycle.
- Do not mark a transaction paid, completed, or accepted as a side effect.
- Do not implement payments or logistics.
- Do not create unsupported database fields, tables, or status transitions.

## 7. Responsive and Accessible Behavior

- Support small screens and different device sizes.
- Use scrolling rather than allowing the form to overflow.
- Ensure text fields remain usable when the keyboard is open.
- Use meaningful labels and semantic selection controls.
- Maintain readable contrast for text, borders, hints, and selected states.
- Ensure buttons have clear enabled, disabled, loading, and error states.
- Prevent accidental duplicate submissions.

## 8. Required Implementation and Verification

Before coding:
1. Inspect project instruction and design files.
2. Inspect the inquiry entry point, listing details, API services, and backend routes/models.
3. Check Git status and preserve unrelated modifications.

Implement:
- Screen layout and components, including the seller name in the listing summary.
- Form state and validation: required message, 500-character ceiling, whitespace rejection.
- Message templates that fill the field without submitting.
- Optional payment and collection preference selections.
- API integration only using verified endpoints and supported fields.
- Loading, success, and error states.
- Correct navigation.
- Relevant widget/service/backend tests as appropriate.

Run relevant checks:
- `dart format` on changed Dart files.
- `flutter analyze`.
- Targeted Flutter tests and the full test suite when feasible.
- Relevant Laravel tests inside the configured PHP Docker container if backend files change.

Do not reset the database or Docker volumes. Do not stage, commit, or push.

## 9. Acceptance Criteria

- The screen visually follows the supplied screenshot and existing AgroBenta design system.
- The summary shows the actual selected listing.
- Form fields have correct state, validation, and conditional behavior.
- Cancel and back navigation work correctly.
- Submission uses a verified backend contract and never displays fake success.
- Unsupported fields are documented rather than silently discarded.
- Loading, server errors, and network errors are handled.
- The UI is usable on small screens and with the keyboard open.
- Relevant tests and analysis have been run and their results reported.
- Existing code, business rules, uncommitted changes, and database data remain intact.

## 10. Completion Report

Report:
- Files created or changed.
- UI and behavior implemented.
- Backend endpoint and request/response contract actually used.
- Fields genuinely persisted versus fields not supported.
- Tests and static analysis run, including results.
- Remaining blockers or backend changes requiring approval.

Do not report full end-to-end completion if the backend cannot persist the inquiry.
