# AgroBenta Mobile UI Design --- Browse Livestock Screen

## Purpose

This specification defines the AgroBenta Flutter **Browse Livestock**
screen based on the supplied reference image.

The screenshot is a visual target only. All listing records, asking
prices, locations, seller data, statuses, and livestock photos must come
from the existing backend API and actual seller-submitted listings. Do
not hardcode sample animals or prices from the reference.

This screen replaces the visible bottom-navigation label **Marketplace**
with **Browse**. Preserve the navigation order defined below.

## 1. Visual Direction

-   Brand: AgroBenta, a trustworthy livestock marketplace.
-   Primary green: approximately `#006B3C`, or reuse the closest
    existing theme green.
-   Background: white or very light neutral.
-   Cards: white with subtle cool-gray borders or restrained shadows.
-   Metadata: muted slate-gray text.
-   Category chips: pale gray; selected chip dark green with white text.
-   Listing tags: pale green with dark-green text.
-   Typography: clear titles, prominent green prices, readable secondary
    metadata.
-   Icons: use the existing icon system or installed icon package. Never
    use emoji or arbitrary Unicode glyphs as icons.

Reuse existing theme tokens and shared components instead of introducing
a duplicate design system.

## 2. Screen Structure

### A. Top App Bar

-   Dark agricultural-green header.
-   Centered title: **"Browse Livestock"**.
-   Notification bell on the right only if notification functionality
    exists.
-   Show an unread indicator only when backed by real notification
    state.
-   Respect the device safe area and status bar.
-   Provide an accessible label for the notification action.

### B. Search and Filter Row

-   Rounded search field with a leading search icon.
-   Reference placeholder: **"Search livestock in Trinidad, Bohol..."**.
-   Separate outlined filter button on the right.
-   The location in the placeholder is illustrative only. Do not
    hardcode Trinidad, Bohol as the user's location or filter by it
    unless explicitly selected or provided by approved app state.
-   Use existing search/filter behavior and supported API parameters.
-   If a filter is unsupported, do not fabricate behavior or add API
    parameters without approval.

### C. Category Filter Chips

Reference order: 1. All 2. Cattle 3. Swine 4. Goat 5. Carabao

-   Use only categories supported by the approved taxonomy.
-   "All" clears the category filter.
-   Selecting a category updates results using existing supported
    filtering.
-   Selected chip: dark-green fill and white text.
-   Unselected chips: light surface and subtle border.
-   Allow horizontal scrolling on narrow screens.
-   If API taxonomy uses a different canonical value, map the display
    label to the existing value without changing the backend contract.

### D. Livestock Listing Cards

Use a vertically scrolling list of horizontal cards: - Left: square or
near-square livestock image with rounded corners. - Right: listing
title, green asking price, location row, and compact attribute tags. -
Heart/favorite action only if favorites are supported by the current
app/API. - White card with subtle border or shadow and rounded corners.

**Dynamic data rules** - Every listing card must use a real listing
record returned by the existing backend API. - Titles, asking prices,
location, images, and attributes must come from actual seller-submitted
data and the approved API response. - Buyer browsing must continue to
show active listings only. - Do not hardcode the sample names or prices
from the image, including Brown Cattle, Native Pig, Boer Goat, Carabao,
₱45,000, ₱8,000, ₱12,000, or ₱50,000. - Do not fabricate age, health,
condition, growth stage, ratings, seller identity, or location. -
Display tags only when supplied by the API or supported by the approved
model. - Do not synthesize image URLs. Use image data returned by the
existing API. - If no image exists, use an existing branded or neutral
placeholder. - If a field is absent, omit it rather than infer it. -
Reuse the current listing model, repository, service, and controller. Do
not create a second API layer. - Preserve existing pagination and
server-side filtering.

### E. Loading, Empty, and Error States

-   Use a restrained loading indicator or existing skeleton pattern.
-   For no matching listings, show a friendly empty state and offer
    clearing filters if supported.
-   For request failure, show a non-technical message and retry action.
-   Image errors must fall back safely.
-   Never insert fake listings to fill empty space.

## 3. Bottom Navigation --- Required Order

The bottom navigation must use this exact order and labels: 1. **Home**
2. **Browse** 3. **Messages** 4. **Transactions** 5. **Profile**

-   Rename the existing **Marketplace** label to **Browse**.
-   The Browse destination should reuse the existing marketplace screen;
    do not create a duplicate screen.
-   Preserve existing Home, Messages, Transactions, and Profile
    implementations where they exist.
-   Do not add placeholder destinations that lead nowhere. If Messages
    or Transactions are not implemented, report this and ask for
    approval before adding nonfunctional tabs.
-   Use existing installed icons for Home, Browse/search, Messages/chat,
    Transactions/receipt or list, and Profile/person.
-   Keep selected/unselected states consistent; selected destination
    uses primary green.
-   Keep labels visible and accessible.
-   Ensure the bottom bar does not cover scrollable content and preserve
    route/state behavior.

## 4. Icon and Image Requirements

-   Use installed icon packages and existing shared icon components.
-   Do not use emoji or hardcoded glyphs for category, location, search,
    filter, favorite, notification, or navigation icons.
-   Reuse real local assets when available.
-   Livestock photos must come from real listing records or approved
    local placeholder assets.
-   Do not download random images, hardcode remote URLs, or use the
    screenshot's animals as fake content.
-   A favorite icon is interactive only if favorite state and
    persistence are supported.

## 5. API and Business Rules

-   Reuse the existing marketplace endpoint and data layers.
-   Do not change backend endpoints, schema, or response resources
    solely to match this design.
-   Do not change buyer/seller capability rules or authorization.
-   Do not change the listing lifecycle.
-   Do not expose seller email addresses or private information.
-   Do not invent category API parameters, location inference,
    age/health attributes, or favorite endpoints.
-   If a required field or feature is unavailable, document the gap
    rather than making up data.

## 6. Responsive Behavior and Accessibility

-   Support different Android screen sizes.
-   Use a scrollable listing list and horizontally scrollable category
    chips.
-   Avoid horizontal overflow and clipped card content.
-   Use a consistent image aspect ratio.
-   Respect safe areas and text scaling.
-   Provide accessible labels for icon-only controls.
-   Maintain adequate contrast and comfortable touch targets.
-   Handle loading, empty, network error, and image error states.

## 7. Flutter Implementation Guidance

-   Inspect the existing Browse/Marketplace screen, BuyerShell, listing
    models, repository, service, controller, and tests before editing.
-   Update the existing screen rather than creating a duplicate
    marketplace feature.
-   Follow current feature-first architecture and state-management
    conventions.
-   Reuse existing theme tokens and installed icon dependencies.
-   Avoid adding packages unless needed and approved.
-   Keep temporary logo usage centralized.
-   Do not alter backend APIs or database schema without explicit
    approval.

## 8. Protected Areas and Git Rules

-   Preserve all existing M5/M6 work, Docker performance changes, mobile
    configuration, tests, and uncommitted modifications.
-   Do not modify `frontend/src/index.css`, root `AGENTS.md`, or root
    `DESIGN.md`.
-   Do not reset, clean, revert, or discard Git changes.
-   Do not reset the database or delete Docker volumes.
-   Do not stage, commit, or push to GitHub without explicit user
    consent.

## 9. Acceptance Criteria

1.  Browse follows the reference: green app bar, search/filter row,
    category chips, and horizontal listing cards.
2.  Bottom navigation order is Home, Browse, Messages, Transactions,
    Profile.
3.  Marketplace is renamed to Browse, not duplicated.
4.  Listing cards use real seller-submitted API data only.
5.  No fake prices, locations, animal attributes, ratings, or images are
    introduced.
6.  Category filters use supported existing API behavior.
7.  Unsupported favorites or notifications are not falsely presented as
    working.
8.  Loading, empty, request-error, and image-error states are handled.
9.  `flutter analyze` and relevant tests pass.
10. Existing changes are preserved; nothing is staged, committed, or
    pushed.

## 10. Final Report

Report files changed, how Marketplace was renamed to Browse,
confirmation of navigation order, API/model/assets reused, functional
versus unavailable filters/actions, actual test results, missing API
fields/assets, and confirmation that unrelated changes were preserved
and nothing was staged, committed, or pushed.
