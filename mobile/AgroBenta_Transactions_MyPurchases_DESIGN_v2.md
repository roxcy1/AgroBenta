# AgroBenta Mobile — Transactions / My Purchases Screen Design

## Purpose
Define the buyer-facing **Transactions — My Purchases** screen for AgroBenta Flutter, based on the supplied screenshot. The screenshot is a visual reference only; livestock names, photos, prices, IDs, dates, locations, and statuses shown are examples and must not be hardcoded in production.

## Project Rules
- Read root `AGENTS.md`, root `DESIGN.md`, `mobile/AGENTS.md`, and `mobile/DESIGN.md` before editing.
- Inspect existing Flutter transaction/inquiry flow, API services/models, Laravel routes/controllers/models/resources/migrations, and tests.
- Reuse existing architecture, theme, API client, authentication, state management, navigation, and error handling.
- Preserve backend contracts, authorization, listing lifecycle, transaction workflow, uncommitted changes, and database data.
- Do not invent endpoints, fields, statuses, migrations, IDs, prices, or fake success.
- Do not overwrite project-wide design files. Do not stage, commit, or push.
- Never reset the database or delete Docker volumes.

## App Bar and Heading
- Use the existing AgroBenta green app bar titled **Transactions**.
- Respect status-bar and safe-area insets.
- Display **My Purchases**.
- Show only records belonging to the authenticated user under existing authorization rules.

## Status Filters
Display horizontally scrollable filter chips: **All**, **Pending**, **Ongoing**, **Completed**, **Cancelled**.
- Select All by default unless the app already has an established preference.
- Selected chip uses primary green; unselected chips use neutral backgrounds.
- Filter using actual backend statuses or a verified, semantically correct mapping.
- Do not add statuses to match the screenshot.
- Do not treat an inquiry as a transaction unless the approved backend workflow explicitly converts it.
- If backend status names differ, document the mapping instead of assuming equivalence.

## Transaction Cards
Show actual data when available:
- Listing photo and listing/livestock title.
- Actual agreed transaction price, if an agreement and persisted transaction price exist.
- Explicit price label distinguishing agreed transaction price from the listing's reference asking price.
- Listing location, if available and appropriate.
- Current status.
- Real transaction ID.
- Correct requested/created date and time from the corresponding backend timestamp.
- Status description only if supported by the actual workflow.
- Chevron only when a transaction details destination exists.

Rules:
- Populate cards from the authenticated API response.
- Never hardcode screenshot examples such as Brown Cattle, Boer Goat, Native Pig, sample prices, locations, dates, IDs, or status messages.
- Do not fabricate image URLs.
- Never display a listing reference price as an agreed transaction price.
- If price has not been agreed, show a neutral message only if it accurately reflects the actual workflow.
- Handle missing optional values and long text without overflow.
- Use backend ordering/pagination if specified by the endpoint.

## Status Styling
The reference illustrates Pending (amber/yellow), Ongoing (blue), Completed (green), and Cancelled (neutral/error style). Use these only when they accurately represent backend status. Do not invent status values or transitions.

## Business Rules
- A purchase inquiry is not automatically a confirmed transaction.
- Do not create a transaction just because an inquiry was sent.
- Do not mark a transaction completed, paid, or cancelled from this screen unless the approved workflow supports that action.
- Do not imply payment or logistics functionality.
- Opening/filtering this screen must not change a listing's lifecycle state.
- Price and status must come from a real persisted transaction record.
- Follow Laravel authorization and ownership rules.
- Do not add schema fields, status transitions, or migrations without approval.

## Transaction Details Navigation
- Tapping a card opens the existing transaction details screen if implemented.
- Pass the real transaction identifier.
- Load details through an authorized backend endpoint.
- Do not present listing details as transaction details.
- If details are unsupported, report the missing route/API rather than creating a fake destination.
- Preserve the existing navigation shell and selected tab.

## Loading, Empty, and Error States
Implement loading indicator/skeleton, empty state when there are no records, empty filtered results, recoverable API/network error with retry, and expired-auth handling consistent with the app. Add pagination or refresh only if supported by the existing endpoint/conventions. Never fill an empty list with sample transactions.

## Bottom Navigation
Use existing order: Home, Browse, Messages, Transactions, Profile. Highlight Transactions while active. Reuse the current navigation shell; do not create a duplicate bar or fake destinations.

## Visual Design
- Green app bar and selected filter.
- White/near-white background.
- White transaction cards with subtle borders and rounded corners.
- Listing image at left and details at right where space permits.
- Accurate status chips with accessible colors and existing icons.
- Muted grey supporting text.
- Compact secondary row for transaction ID and date.
- Consistent typography and spacing with the existing AgroBenta theme.
- Responsive scrolling; avoid fixed heights that cause overflow.

## API and Backend Inspection
Identify the actual endpoint and response fields for fetching the authenticated user's purchases, filtering by status, retrieving details, agreed price, and relevant timestamps. Inspect Laravel routes, controllers, models, resources, policies, migrations, and tests. Use the existing authenticated API client.

If an endpoint or field is missing, do not invent it or imply data exists. Do not add schema changes without approval. Implement only supported behavior and report the exact gap and smallest compatible proposed change.

## Testing and Verification
Before coding, read project instructions, inspect Flutter/Laravel inquiry and transaction code, verify actual statuses/response fields, and check Git status.

Add or update tests for real card rendering, all filters, backend-to-UI status mapping, loading/empty/error/retry states, details navigation using the correct transaction ID, missing optional values and long text, authenticated-user data isolation, and absence of fabricated prices/IDs/timestamps/statuses.

Run `dart format` on changed Dart files, `flutter analyze`, relevant Flutter tests, and Laravel tests inside the configured PHP Docker container if backend files change. Do not reset databases or volumes. Do not stage, commit, or push.

## Acceptance Criteria
- Screen visually follows the screenshot and existing app style.
- Only the authenticated buyer's real records appear.
- All five filters use verified backend statuses.
- Prices and timestamps are correctly labelled and sourced.
- Inquiries are not misrepresented as confirmed transactions.
- Card navigation uses a real transaction ID and supported destination.
- Loading, empty, and error states work.
- No fake records or unsupported fields are introduced.
- Existing code, data, and unrelated changes remain intact.
- Test and analysis results are reported accurately.

## Completion Report
Report files changed, actual API endpoint/fields, backend statuses and UI mapping, details navigation support, missing functionality/backend gaps, and test/analysis results. Do not claim end-to-end completion for unsupported behavior.
