# AgroBenta Mobile — Transaction Status Screen Design

## 1. Purpose
Define the buyer-facing **Transaction Status** screen for AgroBenta Flutter based on the supplied screenshot. It presents the actual purchase request/transaction status and a chronological progress tracker.

The screenshot is a visual reference only. Its listing name, photo, prices, ID, date, location, and current step are examples and must not be hardcoded into production.

## 2. Project Rules
- Read root `AGENTS.md`, root `DESIGN.md`, `mobile/AGENTS.md`, and `mobile/DESIGN.md`.
- Inspect existing Flutter transaction details/status screens and Laravel transaction, inquiry, messaging, notification, and status-history implementation before editing.
- Reuse existing architecture, theme, API client, authentication, state management, navigation, and error handling.
- Preserve existing backend contracts, authorization, listing lifecycle, transaction workflow, uncommitted changes, and database data.
- Do not invent endpoints, fields, status values, transition rules, notifications, timestamps, or fake success.
- Do not overwrite project-wide design files.
- Do not stage, commit, or push. Do not reset databases or delete Docker volumes.

## 3. App Bar
- Green app bar titled **Transaction Status**.
- Back arrow returns to the existing Transaction Details screen or previous route.
- Respect safe areas and existing navigation shell.

## 4. Listing and Request Summary
Display real data associated with the selected transaction/request:
- Listing image if a supported image URL/asset exists.
- Listing title.
- Actual agreed price only if the backend records an agreement.
- A distinct reference asking price label where available.
- Current status badge.
- Location and listing attributes only when present in real data.
- Transaction/request ID.
- Requested date/time from the correct persisted timestamp.

Rules:
- Load the record using its real identifier.
- Never hardcode screenshot examples such as Brown Cattle, sample prices, IDs, dates, or location.
- Never present a listing reference price as a confirmed agreed price.
- Do not fabricate image URLs or status values.
- Handle missing optional values without misleading placeholders.

## 5. Transaction Progress Timeline
The reference displays these five conceptual steps:
1. **Purchase Request Submitted**
2. **Pending Seller Confirmation**
3. **Seller Accepted**
4. **Arrange Delivery**
5. **Confirm Receipt / Mark as Completed**

Before implementing these exact steps, inspect the current backend workflow and approved business rules. Render only steps and transitions that are actually supported. Do not add database statuses or transitions simply to match the screenshot.

### Timeline presentation
- Vertical timeline with numbered/status markers.
- Completed steps use the existing green success style.
- Current step uses an accessible highlighted status color and icon.
- Future steps use neutral outlined markers.
- A connecting line visually indicates progress.
- Each step may include a title, date/time, and explanatory text only if supported by actual status/history data.
- The current step must be derived from the backend status, not a hardcoded screenshot value.
- If the backend has no status-history timestamps, do not fabricate dates for each step.
- If the backend only exposes one current status and no transition history, show a simple status summary and clearly indicate that a historical timeline is not available; do not imply that every step has been recorded.

### Business meaning
- Sending an inquiry does not necessarily create a purchase request or transaction.
- A purchase request is not the same as seller acceptance.
- Seller acceptance must be a real server-confirmed state.
- Delivery arrangements are coordination only; do not imply AgroBenta books or provides logistics.
- Receipt/completion may be confirmed only through the actual approved workflow.
- Do not imply payments or payment processing.

## 6. Status Explanations and Notifications
- Use short explanatory copy that matches the real current status.
- Do not promise a notification unless notification delivery is implemented.
- If the backend supports notifications, use the actual notification flow.
- Do not generate fake status updates or dates on the client.
- Refresh or reload status from the authenticated API according to existing app patterns.

## 7. Message Seller Action
The screenshot shows a full-width **Message Seller** button.

Implement it only if the messaging workflow supports opening the relevant seller conversation:
- Open the existing conversation if one is linked.
- Otherwise use an approved conversation-start flow.
- Pass the real conversation/listing/request identifier required by the actual contract.
- Do not invent a messaging endpoint, fake a conversation, or send an automatic message.
- Do not expose private seller contact information.
- If messaging is unsupported, hide/disable the action or explain the limitation consistently with the app.

## 8. Loading, Error, and Refresh
Implement:
- Loading state for status details.
- Recoverable API/network error with retry.
- Authentication-expired handling.
- Safe behavior when a record is missing or the user is unauthorized.
- Refresh/reload only in line with existing app conventions.
- No fabricated timeline or sample status when loading fails.

## 9. Bottom Navigation
Use the existing navigation order:
1. Home
2. Browse
3. Messages
4. Transactions
5. Profile

Highlight Transactions. Reuse the existing navigation shell; do not add a duplicate bottom bar.

## 10. Visual Design
- Green app bar and white/near-white background.
- Listing summary card with image and key price/status information.
- Compact metadata card for ID and requested date/time.
- Heading **Transaction Progress**.
- Vertical timeline with completed/current/upcoming states.
- A pale green information card where appropriate.
- Full-width green **Message Seller** action.
- Existing AgroBenta typography, spacing, colors, and icon package.
- Responsive scrolling; avoid fixed heights that cause overflow.
- Maintain accessible contrast and clear status labels.

## 11. Backend and Security Inspection
Inspect actual Laravel routes/controllers/models/resources/policies/tests for:
- Fetching transaction/request details.
- Current status and supported transitions.
- Status history or timestamps.
- Seller identity/display fields.
- Messaging/conversation linkage.
- Notification support.

Use the authenticated API client and enforce record ownership server-side. Do not trust client-supplied user IDs. Do not add fields, status enums, routes, or migrations without approval. If the backend cannot supply a full timeline, report that limitation and implement only a truthful status view.

## 12. Testing
Add or update tests for:
- Correct record loading by identifier.
- Current status rendering.
- Mapping backend status to timeline state.
- Timeline behavior when history is missing.
- No invented timestamps or statuses.
- Loading, error, missing-record, and unauthorized states.
- Message Seller navigation only when supported.
- Correct reference-price/agreed-price distinction.
- Authenticated-user data isolation.

Run `dart format` on changed Dart files, `flutter analyze`, relevant Flutter tests, and relevant Laravel tests inside the configured PHP Docker container if backend files change. Do not reset databases/volumes. Do not stage, commit, or push.

## 13. Acceptance Criteria
- Screen visually follows the reference and existing AgroBenta theme.
- Listing/request summary comes from real authorized data.
- Timeline accurately represents the actual workflow.
- Current status and timestamps are not fabricated.
- Message Seller works only through a verified messaging flow.
- Missing history or backend features are handled honestly.
- No payment, logistics, or transaction confirmation is implied without backend support.
- Existing code, data, and uncommitted changes remain intact.
- Tests and analysis results are reported accurately.

## 14. Completion Report
Report files changed, actual API endpoints/fields, real backend status values, whether status history exists, messaging support, tests run, and remaining backend gaps. Do not claim a full historical timeline unless the backend actually records and returns that history.
