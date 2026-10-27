# AgroBenta Mobile — Inquiry Sent Screen Design

## 1. Purpose

This document specifies the **Inquiry Sent** confirmation screen in the AgroBenta Flutter mobile application, based on the supplied screenshot. It follows the Inquire About Livestock form and summarizes the submitted inquiry for the buyer.

**Important:** Show this screen as a successful-submission confirmation only after the backend confirms that the inquiry was persisted. Do not display a fake confirmation or fabricate an inquiry record or status.

## 2. Implementation Principles

- Follow the root `AGENTS.md`, root `DESIGN.md`, `mobile/AGENTS.md`, and `mobile/DESIGN.md`.
- Reuse the existing theme, widgets, navigation shell, API client, models, and state-management approach.
- Inspect the existing inquiry form design and implementation before editing.
- Preserve all current backend contracts, listing lifecycle rules, authentication, authorization, uncommitted changes, and database data.
- Do not invent endpoints, database columns, migrations, response fields, or status transitions.
- Do not hardcode sample listing details or inquiry content in production.
- Do not stage, commit, or push. Do not reset databases or remove Docker volumes.

## 3. Screen Layout

### 3.1 App Bar

- Use the existing AgroBenta green app-bar style.
- Back arrow on the left.
- Centered title: **Inquiry Sent**.
- Respect system status-bar and safe-area insets.

### 3.2 Success Indicator

Near the top of the page:
- Display a green check icon inside a pale green circular background.
- Use the existing icon package; do not use emoji or arbitrary Unicode glyphs.
- Provide a clear success heading: **Your inquiry has been sent to the seller.**
- Supporting text: **You’ll be notified when the seller responds.**

Only show this success state after confirmed server-side submission. If the server request fails, remain on the form and show the actual error rather than navigating here.

### 3.3 Livestock Summary Card

Show the actual listing associated with the submitted inquiry:
- Listing image, only when a valid supported image URL or asset exists.
- Listing/livestock title.
- Asking price formatted in Philippine pesos (₱).
- The label **(Reference Price)** if consistent with the current listing display convention.
- Location.
- Category and other attributes only when provided by the real listing data.

Requirements:
- Use the listing ID from the submitted inquiry or its verified response.
- Do not hardcode the screenshot's Brown Cattle, ₱45,000, Trinidad, Bohol, or attributes.
- Do not fabricate image URLs or listing attributes.
- Treat the displayed asking price as reference-only, not a confirmed transaction price.
- Provide a placeholder if the listing has no usable image.

### 3.4 Your Inquiry Summary

Present a compact, readable summary with an icon, field label, and value for each supported item.

Screenshot fields:

1. **Subject** — e.g. General Inquiry.
2. **Message** — the submitted message.
3. **Interested in purchasing?** — Yes or No.
4. **Transaction preference** — Direct Deal or Arrange Delivery.
5. **Delivery fee** — show an actual saved value or a neutral message such as “To be agreed with seller” only when that is the real, approved workflow.
6. **Preferred contact method** — e.g. In-app Message.

Rules:
- Use values from the confirmed saved inquiry or retained submission state that is consistent with the server response.
- Do not show a value as saved if it was never submitted or persisted.
- If a field is not supported by the current backend contract, do not fabricate its value. Omit it or use an explicitly approved display-only representation.
- Truncate long messages in the summary only if necessary for layout, and provide a way to view the full inquiry through the inquiry details screen.
- Do not expose private seller information.

### 3.5 Inquiry Status Card

The screenshot uses a pale amber/yellow status card with a clock icon.

Suggested visual hierarchy:
- Clock icon inside an amber circular background.
- Label: **Inquiry Status**.
- Status heading: **Awaiting seller response**.
- Supporting text: **You’ll receive a notification once the seller replies to your inquiry.**

Important status rules:
- Use the actual status returned by the backend, if an inquiry status exists.
- Do not invent a status enum or database field.
- Show “Awaiting seller response” only if the actual state and workflow support that meaning.
- Do not imply that a push notification is configured unless notification delivery is actually implemented.
- If the backend has no inquiry-status model, document that limitation and do not simulate a persistent status.

## 4. Actions

### 4.1 View Inquiry

- Primary full-width green button with label **View Inquiry** and a right-chevron icon.
- Open the existing inquiry detail destination, if implemented.
- Pass the actual inquiry ID or stable identifier.
- The detail view should display the saved inquiry, its listing context, and real status.
- Do not create a fake details screen or route to an unrelated transaction.
- If no inquiry detail screen or endpoint exists, report the missing functionality rather than inventing an API contract.

### 4.2 Back to Browse

- Secondary full-width outlined green button with label **Back to Browse** and a left-chevron icon.
- Navigate to the existing Browse destination.
- Reuse the current navigation shell; do not create a duplicate bottom navigation bar.
- Preserve the user's authentication and existing application state.
- Avoid resubmitting the inquiry when navigating back or reopening the screen.

## 5. Bottom Navigation

Match the existing AgroBenta navigation order, where implemented:
1. Home
2. Browse
3. Messages
4. Transactions
5. Profile

- Use the existing app shell and icon package.
- Highlight Browse as shown in the reference if that is consistent with the app's navigation model.
- Do not create placeholder destinations or duplicate navigation bars.
- Ensure the confirmation screen does not stack another bottom navigation bar on top of the shell.

## 6. Visual Design

Follow the supplied screenshot and existing AgroBenta theme:
- Green app bar and primary action.
- White or near-white background.
- Pale green success circle and check.
- Dark, readable confirmation heading.
- Muted grey supporting text.
- White summary cards with subtle neutral borders and rounded corners.
- Pale amber status card with a clock icon.
- Clear spacing and alignment between summary rows.
- Consistent typography and icon sizes.
- Scrollable content on smaller screens.
- Respect safe areas and bottom navigation insets.
- Avoid hardcoded heights that can cause overflow.

## 7. Data and Security

- The confirmation must be linked to the real saved inquiry.
- Do not trust a client-supplied user ID.
- Obtain inquiry data through the authenticated API and existing authorization rules when loading persisted details.
- Do not expose seller-private information.
- Do not create a transaction simply because an inquiry was sent.
- Do not change the listing status to SOLD or otherwise alter the listing lifecycle.
- Do not imply payment, seller acceptance, delivery booking, or a confirmed appointment.
- The listing asking price remains reference-only.
- Do not add unsupported tables, columns, endpoints, or status transitions without approval.

## 8. Navigation and Error Handling

- Enter this screen only after confirmed successful inquiry creation.
- Retain the actual inquiry and listing identifiers.
- Handle a missing or malformed response safely.
- Handle unauthorized/expired sessions and network errors using existing app conventions.
- If loading inquiry details fails, show a recoverable error state rather than fabricated details.
- Prevent accidental duplicate submission in the preceding form.
- Ensure the system Back action behaves consistently with the existing navigation flow.

## 9. Required Implementation and Testing

Before coding:
1. Read applicable project instruction and design files.
2. Inspect the implemented inquiry form, its submission service, API response, navigation shell, and listing details.
3. Inspect relevant Laravel routes, controllers, models, resources, authorization, and tests.
4. Check Git status and preserve unrelated changes.

Implement:
- Confirmation layout and success state.
- Real listing and inquiry summary data.
- Status presentation based on supported backend state.
- View Inquiry navigation when the destination exists.
- Back to Browse navigation.
- Loading/error/empty handling as applicable.

Tests should cover:
- Screen rendering from real/mock test fixtures.
- No confirmation display after failed submission.
- Correct listing and inquiry summary values.
- Supported status rendering.
- View Inquiry uses the correct inquiry identifier.
- Back to Browse navigation.
- Missing optional fields and long messages.
- API errors and malformed responses.
- No duplicate inquiry submission.

Run:
- `dart format` on changed Dart files.
- `flutter analyze`.
- Targeted Flutter tests and full tests when feasible.
- Relevant Laravel tests inside the configured PHP Docker container if backend files change.

Do not reset the database or Docker volumes. Do not stage, commit, or push.

## 10. Acceptance Criteria

- The screen visually follows the supplied screenshot and existing AgroBenta design.
- It appears only after the server confirms inquiry creation.
- All displayed listing and inquiry details come from actual data.
- Status wording reflects the actual backend workflow.
- View Inquiry opens the correct existing detail destination when supported.
- Back to Browse works and does not resubmit the inquiry.
- Missing backend support is reported rather than faked.
- Layout works on small screens.
- Relevant tests and static analysis results are reported.
- Existing code, database data, and unrelated changes remain intact.

## 11. Completion Report

Report:
- Files created or modified.
- UI and navigation implemented.
- Actual backend endpoint and response contract used.
- Fields and statuses that are genuinely persisted/supported.
- Tests and analysis commands run, with results.
- Remaining blockers or backend changes requiring approval.

Do not claim end-to-end completion if inquiry persistence, status, or details retrieval is not supported by the backend.
