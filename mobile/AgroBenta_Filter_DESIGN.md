# AgroBenta Mobile UI Design --- Filter Livestock Screen

## Purpose

This specification describes the AgroBenta Flutter **Filter Livestock**
screen based on the supplied reference image. The screenshot is a visual
target; filter values and results must use the existing supported
marketplace data and API contract. Do not hardcode a location or
introduce unsupported filter parameters.

## 1. Visual Direction

-   Header: dark agricultural green with white title and controls.
-   Background: white or very light neutral.
-   Sections: white rounded panels with subtle light-gray borders.
-   Primary selection/action: deep green with white text.
-   Unselected chips: pale gray with dark text.
-   Secondary action: white background, green border and text.
-   Typography: compact, clear, accessible headings and labels.
-   Icons: use the existing icon package and shared components, never
    emoji or arbitrary Unicode glyphs. Reuse existing AgroBenta theme
    tokens and components.

## 2. Header

-   Back arrow on the left.
-   Centered title: **"Filter Livestock"**.
-   **Reset** action on the right.
-   Respect safe areas and status bar.
-   Back returns to Browse without applying pending changes unless
    current app behavior specifies otherwise.
-   Reset clears the form to defined defaults but does not submit it.
-   Provide accessible labels for icon-only controls.

## 3. Animal Type

-   Heading: **"Animal Type"**.
-   Reference order: Cattle, Swine, Goat, Carabao.
-   Each tile contains a proper livestock icon and label.
-   Selected tile: green border, pale-green surface, green icon/text.
-   Unselected tiles: light-gray surface and dark icon/text.
-   Use approved category values mapped to canonical backend values.
-   If multi-select is unsupported, preserve the existing single-select
    behavior.
-   Use existing icon packages or approved local assets, not emoji.

## 4. Price Range

-   Heading: **"Price Range"**.
-   Two side-by-side numeric fields: **Min Price (₱)** and **Max Price
    (₱)**.
-   Use numeric keyboard input and existing currency conventions.
-   Validate non-negative values and ensure minimum does not exceed
    maximum.
-   Blank values mean unset unless the existing contract specifies
    otherwise.
-   Do not hardcode the screenshot's sample values as defaults.
-   Send only query parameters supported by the existing API. Report
    unsupported price filtering rather than inventing a contract.
-   Parse input safely.

## 5. Location

-   Heading: **"Location"**.
-   Full-width selection row with location icon, selected text, and
    dropdown indicator.
-   "Trinidad, Bohol" is an example only; do not hardcode it as the
    user's location/default unless selected or supplied by approved app
    state.
-   Reuse existing location selection/filter support.
-   If unsupported, do not create fake options or imply functionality.
    Report the gap and ask before expanding the API.
-   Do not request device-location permission just to match the design.

## 6. Condition

-   Reference options: **All**, **Young**, **Adult**, **Pregnant**.
-   Selected option uses green fill and white text; unselected options
    use pale gray.
-   Map only to attributes and canonical values supported by the current
    listing model/API.
-   Do not infer condition from title, age, species, or image.
-   If unsupported, report the gap instead of inventing parameters or
    fields.

## 7. Health Status

-   Reference options: **All**, **Healthy**, **Needs Care**.
-   Use the same selected/unselected styles as Condition.
-   Apply only if the approved data model/API supports health status.
-   Do not fabricate health claims or infer health from images.
-   If unsupported, report the limitation and avoid fake filtering
    behavior.

## 8. Sort By

-   Heading with sort icon: **"Sort By"**.
-   Dropdown reference value: **"Newest First"**.
-   Use only sort options supported by the existing API or client
    behavior.
-   Check the endpoint before assuming newest-first sorting is
    supported. If unsupported, preserve existing order and report the
    gap.

## 9. Bottom Actions

Two equal-width buttons: - **Cancel** --- outlined green. - **Apply
Filters** --- filled green.

Behavior: - Cancel closes the filter screen and discards unsubmitted
edits. - Apply validates inputs, applies supported filters, and returns
to Browse with resulting state. - Preserve active filters on reopening
if consistent with current state management. - Show validation without
clearing input. - Never send unsupported query parameters. - Prevent
duplicate submissions.

## 10. Browse Bottom Navigation

Required order: 1. **Home** 2. **Browse** 3. **Messages** 4.
**Transactions** 5. **Profile**

-   Browse is selected.
-   Marketplace remains the same underlying destination with visible
    label **Browse**.
-   Reuse existing routes and icons.
-   Do not add nonfunctional placeholders for unfinished
    Messages/Transactions. Report missing destinations instead.
-   Follow the existing architecture for whether bottom navigation
    appears on the filter route.

## 11. Data and API Rules

-   Inspect existing Browse/Marketplace service, repository, controller,
    listing model, endpoint, and supported query parameters first.
-   Reuse the current filter/state pattern.
-   Only apply filters supported by the current API or existing
    client-side behavior.
-   Do not add endpoints, query parameters, schema columns, or
    migrations without explicit approval.
-   Do not hardcode location, prices, condition, health, or sample
    listings.
-   Preserve buyer visibility: only active listings are visible.
-   Preserve authorization, seller approval, and listing lifecycle
    rules.

## 12. Responsive and Accessibility

-   Support different Android sizes.
-   Allow vertical scrolling on short screens and while the keyboard is
    open.
-   Keep price fields side by side when possible; adapt on narrow
    screens.
-   Prevent keyboard overflow and clipped buttons.
-   Respect safe areas and text scaling.
-   Use semantic labels, accessible selected states, and comfortable
    touch targets.
-   Show validation, loading, and API errors consistently.

## 13. Flutter Implementation

-   Inspect the existing Browse/Marketplace filter screen and navigation
    before editing.
-   Reuse current models, services, repositories, controllers, and theme
    components.
-   Avoid duplicate API calls and duplicate filter implementations.
-   Use installed icon dependencies; ask before adding packages.
-   Do not modify backend APIs or database schema solely to match the
    screenshot.

## 14. Protected Areas and Git Rules

-   Preserve all existing M5/M6 work, Docker fixes, mobile
    configuration, tests, and uncommitted modifications.
-   Do not modify `frontend/src/index.css`, root `AGENTS.md`, or root
    `DESIGN.md`.
-   Do not reset, clean, revert, or discard Git changes.
-   Do not reset the database or delete Docker volumes.
-   Do not stage, commit, or push to GitHub without explicit user
    consent.

## 15. Acceptance Criteria

1.  Filter screen follows the reference layout and green/white styling.
2.  Animal types use approved category values and proper icons.
3.  Price validation works and screenshot values are not hardcoded
    defaults.
4.  Location is not hardcoded and is selectable only if supported.
5.  Condition and health options filter real supported attributes only.
6.  Sorting uses supported behavior.
7.  Reset, Cancel, and Apply Filters work correctly.
8.  Bottom navigation order is Home, Browse, Messages, Transactions,
    Profile where shown.
9.  Active-listing visibility and authorization remain unchanged.
10. `flutter analyze` and relevant filter tests pass.
11. Existing changes are preserved; nothing is staged, committed, or
    pushed.

## 16. Final Report

Report files changed, supported filter fields/parameters, unsupported
options, actual test results, and confirmation that unrelated work was
preserved and nothing was staged, committed, or pushed.
