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
- Location.
- Category and other attributes only when supplied by the real listing data.

Requirements:
- Preserve the actual listing ID throughout the workflow.
- Populate the card from the listing selected on the previous screen.
- Preserve image proportions and show an appropriate placeholder/error state when no usable image is available.
- Do not fabricate photo URLs or infer missing listing attributes.
- Treat the asking price as reference-only, not as a confirmed transaction price.

### 3.3 Your Inquiry

#### Subject
- Label: **Subject**.
- Dropdown with **General Inquiry** as the initial selection.
- Add other subject options only if supported by approved requirements.
- Persist the selected value only if the backend contract supports it.

#### Message
- Label: **Message \\***.
- Multiline text input, required, maximum 500 characters.
- Show a live character counter in `currentLength/500` format.
- Placeholder: `Type your inquiry here...`
- Optional helper text may give examples such as asking about availability, additional photos, or the asking price.
- Reject whitespace-only messages and show a clear validation message.
- Preserve entered text after failed submission.

#### Purchase Interest
- Label: **Are you interested in purchasing? \\***.
- Required Yes/No choice using accessible radio controls.
- Do not assume a selection unless approved requirements specify a default.
- Include the selected value in the request only if supported by the backend contract.

### 3.4 Transaction Method (Preferred)

Present two selectable cards:
1. **Direct Deal** — “I will transact directly with the seller.”
2. **Arrange Delivery** — “I will arrange for the transportation.”

Visual behavior:
- Two cards side by side when space permits.
- Green border and subtle green-tinted background for the selected card.
- Neutral border and background for unselected cards.
- Use existing project icons, not emoji or arbitrary Unicode glyphs.
- Provide accessible selection semantics and a clear selected state.

Business behavior:
- Treat the selection as the buyer's preference only.
- It must not create or confirm a transaction, payment, delivery booking, or seller agreement.
- Do not invent a default selection if requirements do not define one.
- Enforce required selection only if the approved workflow requires it; do not infer requiredness solely from the screenshot's asterisk.

### 3.5 Delivery Details

Implement conditional behavior only to the extent supported by approved requirements and the existing backend.

#### Delivery Method
- Dropdown styled consistently with the other controls.
- Buyer pickup description: **Buyer Pickup (I will get the livestock)**.
- Show arranged delivery only if the approved workflow supports it.
- Do not imply that AgroBenta provides transportation, booking, dispatch, or tracking.

#### Delivery Fee (₱)
- Numeric amount input with a peso label or prefix.
- Reject negative and nonnumeric values.
- For buyer pickup, display ₱0 and prevent inconsistent nonzero input.
- For arranged delivery, accept an amount only if approved requirements permit the buyer to enter a proposed/agreed fee.
- Do not imply the fee is calculated, guaranteed, or confirmed by AgroBenta.
- Do not add the fee to the asking price as a checkout total.
- Persist the value only if the API supports it.

#### Preferred Contact Method
- The screenshot shows **In-app Message**.
- Reuse this option if it matches actual messaging functionality.
- Show other contact methods only when supported and approved.
- Do not reveal private seller contact details to populate this field.

#### Preferred Schedule (Optional)
- Optional date selector with a calendar icon.
- Allow the field to remain empty.
- Apply past-date restrictions only if they match approved requirements.
- A selected date is a preference/request, not a confirmed appointment.
- Persist the date only if the backend supports it.

### 3.6 Bottom Actions

Buttons:
- **Cancel** — outlined green button.
- **Send Inquiry** — filled green primary button.

Cancel behavior:
- Navigate back to the previous screen.
- Use the existing unsaved-changes confirmation pattern if applicable.
- Never submit data when cancelling.

Send Inquiry behavior:
- Validate required fields.
- Prevent repeated taps while a request is in progress.
- Display a loading state during submission.
- Use the existing authenticated API client and real backend contract.
- Show success only after the server confirms successful persistence.
- Show useful validation, authorization, network, timeout, and server errors.
- Preserve form input on failed submission.
- Do not fabricate success or silently discard unsupported fields.

If no backend endpoint and persistence model exist, do not invent one or repurpose messaging/transaction endpoints. Complete the UI and local validation that can be supported, then document the exact backend gap. Do not claim end-to-end completion until real server-side submission is implemented.

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
- Screen layout and components.
- Form state and validation.
- Conditional delivery behavior.
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
