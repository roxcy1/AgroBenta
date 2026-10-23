# AgroBenta Mobile — Seller Verification: Basic Information Screen

## Purpose
Collect the seller's basic information as the first step of the seller application. Use only fields supported by the existing approved data model and API.

## Progress Indicator
Show four steps:
1. Basic Information — active.
2. Documents — upcoming.
3. Review — upcoming.
4. Submitted — upcoming.

Use the existing green/neutral progress style and clear step labels.

## Fields
Use the current supported schema. The reference image includes:
- **Full Name** — required if required by the existing contract.
- **Phone Number** — only if supported.
- **Address** — only if supported.
- **Farm/Business Name** — optional only if supported.

Do not add unsupported profile or verification columns. If the backend expects different field names or rules, follow the actual request validation.

## Validation and Interaction
- Validate required fields using existing app patterns.
- Display field-specific, readable errors.
- Preserve values when moving forward/back.
- Avoid clearing entered data when validation fails.
- Do not invent phone-number formats, address lists, or ID-name matching rules beyond approved requirements.
- Provide an informational note: ensure details are accurate and consistent with the identity documents.
- `Next` advances to Documents only when this step passes supported validation.
- Back returns to the Become a Seller introduction or the previous route.

## Visual Design
- Green title bar: `Seller Application`.
- Progress indicator at top.
- Heading: `Basic Information`.
- Supporting line: `Provide your basic details as a seller.`
- Labels above rounded white input fields with subtle grey borders.
- Existing icons may appear beside fields if consistent with the app.
- Bottom full-width green `Next` button.
- Keep the page scrollable and keyboard-safe.

## Data and Security
- Use the authenticated account.
- Do not trust client-supplied user IDs.
- Do not change role/seller capability at this step.
- If the API saves drafts, use the existing contract; otherwise keep state according to the current architecture.
- Do not log personal data.

## Acceptance Criteria
- All displayed fields are backed by existing supported fields.
- Validation and back/next navigation work.
- Values persist between steps according to existing app architecture.
- No role or seller approval changes occur.
