# AgroBenta Mobile — Transactions / My Purchases Screen Design

## Purpose
Define the buyer-facing **Transactions — My Purchases** screen for AgroBenta Flutter, based on the supplied screenshot. The screenshot is a visual reference only; livestock names, images, prices, IDs, dates, locations, and statuses shown there are examples and must never be hardcoded into production.

## Implementation Principles
- Follow root `AGENTS.md`, root `DESIGN.md`, `mobile/AGENTS.md`, and `mobile/DESIGN.md`.
- Inspect the current Flutter navigation, inquiry and transaction flows, API services/models, Laravel routes/controllers/models/resources/migrations, and tests before editing.
- Reuse existing architecture, theme, API client, authentication, state management, navigation, and error handling.
- Preserve existing backend contracts, authorization, listing lifecycle, transaction workflow, uncommitted changes, and database data.
- Do not invent endpoints, fields, statuses, migrations, transaction IDs, prices, or fake success.
- Do not overwrite project-wide design files. Do not stage, commit, or push.
- Never reset the database or remove Docker volumes.

## Screen Layout

### App Bar
- AgroBenta green app bar titled **Transactions**.
- Match existing typography and status-bar styling; respect safe areas.

### Section Heading
- Display **My Purchases**.
- Show only records belonging to the authenticated buyer.

### Status Filters
Display horizontal chips:
- **All**
- **Pending**
- **Ongoing**
- **Completed**
- **Cancelled**

Behavior:
- All is selected initially unless the app already defines another default.
- Selected chip uses primary green; unselected chips use neutral backgrounds.
- Selecting a filter updates the list using actual backend statuses or a verified UI mapping.
- Support horizontal scrolling on narrow screens.
- Do not add statuses or classify an inquiry as a transaction unless the approved backend workflow explicitly does so.
- If backend status names differ, document the accurate mapping; never map semantically different states together.

### Purchase / Transaction Cards
Show actual values where available:
- Listing photo.
- Listing/livestock title.
- Actual agreed transaction price, if a transaction and agreed price exist.
- A clear label distinguishing agreed price from a listing's reference asking price.
- Listing location, if available and appropriate.
- Actual current status.
- Transaction ID.
- Date requested or transaction date using the correct backend timestamp.
- Short status description only when supported by the real workflow.
- Chevron if tapping the card opens an existing transaction detail screen.

Rules:
- Populate from the real authenticated API response.
- Never hardcode screenshot examples such as Brown Cattle, Boer Goat, Native Pig, sample prices, IDs, locations, or dates.
- Do not fabricate image URLs, transaction IDs, dates, agreed prices, or status text.
- Do not display a listing's reference asking price as an agreed transaction price.
- If the price is not yet agreed, show an accurate neutral label only if it matches the approved workflow.
- Handle missing optional fields and long text without overflow.
- Respect ownership and privacy rules.

### Status Presentation
The screenshot illustrates Pending (amber), Ongoing (blue), Completed (green), and Cancelled (neutral/error style). Use these visual styles only when the actual backend status supports the meaning. Do not invent status values or lifecycle transitions.

## Business Rules
- A purchase inquiry is not automatically a confirmed transaction.
- Do not create a transaction just because an inquiry was sent.
- Do not mark a transaction completed, paid, or cancelled from this screen unless the approved workflow supports the action.
- Do not imply payment or logistics functionality.
- Do not change listing lifecycle state when opening or filtering this screen.
- Transaction price and status must come from a persisted transaction record.
- Follow Laravel authorization and authenticated-user ownership rules.
- Do not add new statuses, columns, or migrations without approval.

## Transaction Details Navigation
- Tapping a card opens the existing transaction details screen if implemented.
- Pass the real transaction identifier.
- Details must load through an authorized backend endpoint.
- Do not present listing details as transaction details.
- If details are unsupported, report the missing route/API instead of creating a fake destination.

## Loading, Empty, and Error States
Implement:
- Loading indicator/skeleton using existing app patterns.
- Empty state when the buyer has no transactions.
- Empty state for a filter with no matching records.
- Recoverable network/API error with retry.
- Authentication-expired handling consistent with the app.
- Pagination or incremental loading only if supported by the endpoint.
- Refresh behavior only if consistent with existing conventions.
- Never populate an empty screen with sample transactions.

## Bottom Navigation
Use the existing navigation order:
1. Home
2. Browse
3. Messages
4. Transactions
5. Profile

Highlight **Transactions**. Reuse the current navigation shell; do not create a duplicate bottom bar or fake destinations.

## Visual Design
- Green app bar and selected filter.
- White/near-white background.
- White transaction cards with subtle neutral borders and rounded corners.
- Livestock image on the left and details on the right where space permits.
- Status chips with accurate accessible colors and existing icons.
- Muted grey supporting text.
- Transaction ID and date in a compact secondary row.
- Consistent spacing and typography with the existing AgroBenta theme.
- Responsive scrolling and no fixed heights that cause overflow.

## API and Backend Inspection
Identify actual endpoints and response fields for:
- Fetching the authenticated buyer's purchases/transactions.
- Filtering by status.
- Retrieving transaction details.
- Agreed price and relevant timestamps.
Inspect routes, controllers, models, resources, policies, migrations, and tests. Use the existing authenticated API client.

If an endpoint or field does not exist, do not invent it or imply it is persisted. Implement only supported behavior and report the precise backend gap and smallest compatible proposed change. Do not add schema changes without approval.

## Testing and Verification
Before coding:
1. Read project instructions/design files.
2. Inspect existing Flutter and Laravel inquiry/transaction code.
3. Check Git status and preserve unrelated changes.
4. Verify actual status names and response fields from source code.

Test:
- Real transaction card rendering.
- All and individual status filters.
- Accurate backend-to-UI status mapping.
- Loading, empty, error, and retry states.
- Details navigation using the correct transaction ID.
- Missing optional values and long text.
- Authenticated-user data isolation.
- No fabricated prices, IDs, timestamps, or statuses.

Run `dart format` on changed Dart files, `flutter analyze`, targeted/full Flutter tests where feasible, and relevant Laravel tests inside the configured PHP Docker container if backend files change. Do not reset databases or volumes. Do not stage, commit, or push.

## Acceptance Criteria
- Visual design matches the screenshot and existing app style.
- Only the authenticated buyer's real records appear.
- All five filters use verified backend statuses.
- Prices and timestamps are correctly labelled and sourced.
- Inquiries are not misrepresented as confirmed transactions.
- Card navigation uses a real transaction ID and supported destination.
- Loading, empty, and error states work.
- No fake records or unsupported backend fields are introduced.
- Existing code, data, and unrelated changes remain intact.
- Report tests and analysis results accurately.

## Completion Report
Report files changed, API endpoint/fields used, backend statuses and filter mapping, details-navigation support, unsupported functionality/backend gaps, and test/analysis results. Do not claim end-to-end completion for unsupported behavior.
