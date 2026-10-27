# AgroBenta Mobile — Transaction Details Screen Design

## 1. Purpose
Specify the buyer-facing **Transaction Details** screen shown in the supplied screenshot. The screen summarizes a real purchase request/transaction, seller information, livestock details, transaction terms, inquiry history, and available actions.

The screenshot is a visual reference only. The sample cattle, prices, names, IDs, dates, seller badge, messages, and statuses must never be hardcoded into production.

## 2. Project and Safety Rules
- Read root `AGENTS.md`, root `DESIGN.md`, `mobile/AGENTS.md`, and `mobile/DESIGN.md` before editing.
- Inspect existing Flutter transaction/listing/inquiry screens and Laravel transaction, seller verification, messaging, and notification code.
- Reuse existing architecture, API client, authentication, state management, theme, navigation, and error handling.
- Preserve backend contracts, authorization, listing lifecycle, transaction workflow, uncommitted changes, and database data.
- Do not invent endpoints, fields, status values, seller verification badges, phone numbers, transaction records, or successful actions.
- Do not overwrite project-wide design files.
- Do not stage, commit, or push. Do not reset databases or delete Docker volumes.

## 3. App Bar
- Green app bar titled **Transaction Details**.
- Back arrow returns to the existing Transactions list.
- Respect safe areas and current navigation shell.

## 4. Listing and Request Summary Card
Display the actual record's data:
- Listing image, if a supported image URL/asset exists.
- Listing title.
- Actual agreed price if an agreement and persisted agreed price exist.
- Clearly label the listing's reference asking price separately from the agreed price.
- Actual status, e.g. pending seller confirmation only if the backend status truly represents this.
- Location and listing attributes only when present in real data.
- Transaction/request ID and requested date/time from actual persisted fields.

Rules:
- Load using the real transaction/request identifier passed from the list.
- Do not hardcode the screenshot's livestock, prices, IDs, dates, location, or status.
- Do not show a listing reference price as an agreed price.
- If there is only a purchase request and no agreed transaction price, show an accurate neutral value or omit the agreed-price row.
- Do not fabricate photo URLs or attributes.

## 5. Seller Information
Show seller details only when returned by the authorized API:
- Seller display name.
- Verification badge only if the backend confirms the seller is currently approved/verified.
- Location only if available and allowed.

### Contact actions
- Message Seller: open the existing conversation or supported conversation-start flow.
- Call Seller: show only if the backend intentionally exposes an authorized phone number and the project requirements permit direct calls.
- Do not expose private contact data just to populate the UI.
- Do not create a fake conversation or fake phone number.
- If the action is unsupported, hide/disable it with an appropriate explanation rather than pretending it works.

## 6. Livestock Details
Display supported listing attributes in a compact two-column key/value layout, such as:
- Type
- Breed
- Age
- Weight
- Condition

Only render fields that exist in the real listing response. Do not invent defaults such as `Healthy`, age, weight, or breed. Handle null values gracefully and avoid empty misleading rows.

## 7. Transaction Details
Display only fields supported by the actual transaction/request contract:
- Agreed Price.
- Delivery Method.
- Delivery Fee.
- Total Amount.

Rules:
- Do not display a confirmed agreed price unless persisted and agreed according to the actual workflow.
- Delivery method and fee are preferences or values only according to the real workflow; do not imply transport has been booked.
- If delivery fee is still to be agreed, show that only if it accurately reflects the existing business process.
- Do not calculate or show a payable total unless the backend/business rules define how it is calculated.
- Do not implement payment processing or imply payment has occurred.
- Do not invent columns or API fields to match the screenshot.

## 8. Status / Notification Card
A status card may explain the actual current state of the request.
- Use an amber status treatment for pending only when supported by the backend.
- Explain the next step only if it matches the real workflow.
- Do not claim that a notification will be sent unless notifications are implemented.
- Status text must come from a verified backend status mapping, not a hardcoded sample.
- A purchase inquiry/request is not automatically a confirmed transaction.

## 9. Your Inquiry Section
If the record is linked to an actual saved inquiry, show:
- Subject.
- Message.
- Submitted timestamp if supported.
- Expand/collapse control for the inquiry text if useful.

Requirements:
- Use the actual saved inquiry data.
- Do not fabricate message text or timestamp.
- If no inquiry is linked, omit the section or show an accurate empty state.
- Do not expose unrelated conversation messages.

## 10. Bottom Actions
The screenshot shows:
- **View Status**
- **Cancel Request**
- **Message Seller**

Implement only actions supported by the current API and approved workflow.

### View Status
- Open the existing status/details destination or show the actual status on this screen.
- Do not create a duplicate or fake status screen.

### Cancel Request
- Only show/enabled when the current backend state allows cancellation.
- Confirm with the user before submission.
- Submit through a real authorized endpoint.
- Update the UI only after the server confirms the change.
- Do not allow cancellation of completed or otherwise ineligible records.
- Do not invent cancellation status transitions or reason fields.

### Message Seller
- Open the actual conversation for this transaction/request if one exists, or use an approved conversation-creation flow.
- Do not invent a messaging endpoint or create fake messages.
- If unsupported, hide/disable the action and report the missing capability.

Use loading, success, and error states for actions. Prevent duplicate taps. Preserve the current screen and data if a request fails.

## 11. Bottom Navigation
Use the existing navigation order:
1. Home
2. Browse
3. Messages
4. Transactions
5. Profile

Highlight Transactions. Reuse the current shell; do not add a duplicate bottom bar.

## 12. Visual Design
- Green app bar and primary action.
- White/near-white background.
- Rounded cards with subtle neutral borders.
- Listing summary with image and key details.
- Seller section with avatar/fallback and supported actions.
- Livestock and transaction details as readable key/value rows.
- Status card using accessible status colors.
- Inquiry card with expandable content.
- Bottom actions laid out responsively without overflow.
- Use existing theme, typography, and icon package.
- Support small screens, scrolling, safe areas, and keyboard if applicable.

## 13. Backend and Security Inspection
Inspect actual routes, controllers, models, resources, policies, and tests for:
- Fetching transaction/request details.
- Seller public profile and verification state.
- Inquiry retrieval.
- Messaging/conversation navigation.
- Request cancellation.
- Status history or notifications, if supported.

Use the existing authenticated API client. Enforce user ownership on the server. Do not trust client-supplied user IDs. Do not expose private seller information. If an endpoint/field/action is missing, do not invent it; report the exact gap and propose the smallest compatible change. Do not add schema changes without approval.

## 14. Testing
Add or update tests for:
- Loading actual details by the correct identifier.
- Missing or unauthorized record behavior.
- Accurate agreed/reference price display.
- Supported livestock fields and null values.
- Seller verification badge only when confirmed.
- Inquiry summary from actual data.
- Cancel action eligibility, confirmation, success, and failure.
- Message action routing only to a real supported destination.
- Loading, empty, and error states.
- No fake prices, IDs, messages, phone numbers, statuses, or timestamps.

Run `dart format` on changed Dart files, `flutter analyze`, relevant Flutter tests, and relevant Laravel tests inside the configured PHP Docker container if backend files change. Do not reset databases/volumes. Do not stage, commit, or push.

## 15. Acceptance Criteria
- Screen matches the reference design and existing AgroBenta theme.
- All displayed details come from authorized real data.
- Reference asking price and agreed price are clearly distinguished.
- Status accurately reflects the backend.
- Seller contact actions work only where supported and authorized.
- Inquiry content is real and linked to the correct record.
- Cancel Request respects actual workflow rules.
- No fake transaction, message, or success state is introduced.
- Existing code, data, and uncommitted changes remain intact.
- Tests and analysis results are reported honestly.

## 16. Completion Report
Report files changed, actual API endpoints and response fields used, which actions are truly supported, test/analysis results, and any missing backend capability. Do not claim end-to-end completion for unsupported behavior.
