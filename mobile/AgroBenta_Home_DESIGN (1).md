# AgroBenta Mobile Design System --- Buyer Home Screen

## Purpose and Source of Truth

This document defines the visual and interaction rules for the AgroBenta
Flutter Buyer Home screen, based on the latest supplied Home reference
image.

The screenshot is a **visual reference**, not a source of production
marketplace data. The implementation must use the existing backend API
and actual seller-submitted listings for dynamic content.

This file supplements the existing mobile design system. Before
replacing or merging it into `mobile/DESIGN.md`, inspect the current
document and preserve any existing design rules that are still
applicable. Do not overwrite unrelated design specifications.

## 1. Brand and Visual Language

-   **Brand:** AgroBenta --- a friendly, trustworthy livestock
    marketplace.
-   **Mood:** fresh, agricultural, welcoming, and professional.
-   **Primary green:** approximately `#08752F`--`#087A32`; prefer
    existing theme tokens when equivalent values already exist.
-   **Primary action green:** approximately `#00752E`.
-   **Background:** white or very light neutral.
-   **Card/surface:** white, with subtle cool-gray borders or restrained
    shadows.
-   **Secondary surfaces:** pale green for category tiles and light
    section backgrounds.
-   **Text:** near-black or deep navy for headings; muted slate for
    metadata.
-   **Corners:** rounded search fields, banner, category tiles, and
    listing cards.
-   **Spacing:** consistent, compact spacing that preserves readability.
-   **Icons:** use the existing icon system or installed icon package.
    Do not use emoji or arbitrary Unicode glyphs as substitutes for
    icons.

Reuse the existing theme, spacing constants, typography, and reusable
widgets wherever possible. Avoid creating a competing theme system.

## 2. Temporary Logo and Assets

-   Use the temporary AgroBenta logo asset already available in the
    project, if present.
-   Do not redraw, replace, or invent the brand logo.
-   Centralize logo usage so the asset can be replaced later without
    changing multiple screens.
-   Prefer existing local assets for the agricultural hero banner.
-   Do not hardcode remote image URLs.
-   Do not use a seller's listing photo as a permanent marketing banner
    without approval.
-   If no suitable banner asset exists, use a restrained
    green/pale-green placeholder and report the missing asset.
-   Register local assets correctly in `pubspec.yaml` if a required
    existing asset is not yet registered; do not generate or download
    unrelated imagery without approval.

## 3. Home Screen Layout

The page is vertically scrollable. The bottom navigation remains managed
by the existing BuyerShell.

### 3.1 Header

Visual structure: - Temporary AgroBenta logo and wordmark on the left. -
Optional tagline: **"Buy. Sell. Grow. Together."** - Notification action
and user profile/avatar action on the right, only where those actions
are supported.

Rules: - Use the actual authenticated user's information when
available. - Do not invent a profile image URL. - If no profile photo is
available, use the existing generic avatar/icon treatment. - Do not
display fake unread counts or notification dots. - Icon-only actions
must have accessible labels. - Unsupported notification functionality
must not appear operational.

### 3.2 Search and Filter

Visual structure: - Rounded white search bar. - Search icon at the
leading edge. - Placeholder: **"Search livestock, seller, or
location..."** - Filter icon at the trailing edge.

Behavior: - Connect to the existing marketplace search/filter
implementation. - Preserve current debounce, pagination, and query
conventions. - Do not create decorative-only controls. - If a particular
search field or filter is unsupported by the backend, report the
limitation rather than fabricating results or adding an unapproved API
contract.

### 3.3 Hero Banner

Visual structure: - Wide rounded agricultural landscape banner. -
Landscape imagery with green hills and livestock. - Headline: **"Quality
Livestock for a Better Tomorrow"**. - Supporting text: **"Connect with
trusted sellers and grow your opportunities."** - Green CTA: **"Explore
Now"**.

Behavior and assets: - Use an existing approved local banner asset where
available. - Do not hardcode external image URLs or listing content. -
Do not add carousel indicators unless the carousel has actual approved
content and behavior. - The CTA navigates to the existing
marketplace/browse screen. - If the asset is missing, use a simple
branded placeholder and report the gap.

### 3.4 Browse by Category

Visual structure: - Heading: **"Browse by Category"**. - Optional **"See
All"** action only if a real destination exists. - Compact responsive
grid of pale-green tiles with consistent icon placement and labels.

The latest reference emphasizes five categories: - Cattle - Goats -
Pigs - Poultry - Sheep

Rules: - Confirm category labels against the current approved data model
or taxonomy. - Display only categories supported by the current
application requirements. - Use real icons from the existing icon system
or approved local category assets. - Do not use emoji icons. - Prefer a
typed category definition with a stable category ID and icon key/asset
reference. - If categories come from an API, use the API as the source
of truth. - If category taxonomy is static and approved, keep it
centralized rather than embedding repeated icon/label logic in
widgets. - Tapping a category must use existing supported marketplace
filtering behavior.

### 3.5 Featured Livestock

Visual structure: - Heading: **"Featured Livestock"**. - Optional **"See
All"** action only if supported. - Responsive row/grid of compact
cards. - Each card may include a real listing image, listing title,
seller asking price, and available metadata.

Data rules: - Populate cards only from actual seller-submitted listings
returned by the existing backend API. - Never hardcode the screenshot's
example animals, names, prices, locations, or seller details. - Do not
fabricate ratings, review counts, favorites, or seller verification
badges. - Display location, seller name, quantity, and status only if
provided by the approved API response. - The buyer marketplace must
continue to show active listings only. - Do not synthesize image URLs. -
If a listing has no image, use a neutral branded placeholder. - Do not
label a section "Featured" unless the backend provides a featured flag,
endpoint, or approved selection rule. If unavailable, use an accurate
section label or report the gap. - A heart/favorite control must not
look functional unless favorites are supported by existing API/state.

### 3.6 Recent Listings

Visual structure: - Heading: **"Recent Listings"**. - Optional **"See
All"** action only if a valid destination exists. - Compact horizontal
row of listing cards.

Data rules: - Use actual API records, following existing server ordering
where possible. - Do not hardcode sample data or fabricate a
newest-first ordering. - Reuse existing listing models, repositories,
services, and state management. - Do not make duplicate requests if
existing marketplace state can be reused appropriately. - If separate
recent-listing retrieval or newest sorting is unsupported, report the
limitation and use only behavior supported by the current API.

### 3.7 Listing Card Rules

-   Use a consistent image aspect ratio and rounded corners.
-   Show only fields available in the real API response.
-   Format the asking price using existing money-formatting conventions.
-   Never infer seller location, ratings, reviews, or quantity from
    unrelated fields.
-   Never synthesize image URLs.
-   Provide safe loading and image-error states.
-   Provide a neutral branded placeholder for missing images.
-   Navigate to the existing listing-detail screen.
-   Do not show inactive, pending, draft, or otherwise hidden listings
    to buyers.

## 4. Bottom Navigation

The latest reference visually shows five items: - Home - Browse -
Messages - Transactions - Profile

This is a **visual target, not automatic authorization to add unfinished
features**.

Implementation rules: - Inspect the current BuyerShell and completed
feature phases before changing navigation. - Keep the current approved
destinations unless the additional destinations are already implemented
and approved. - Do not create placeholder tabs that lead nowhere. - Do
not introduce Messages or Transactions merely to match the screenshot if
those phases are not complete. - Use consistent icons from the existing
icon package. - Ensure selected/unselected states, labels, semantics,
and touch targets are accessible. - If the design target cannot be fully
matched because some destinations are unfinished, preserve working
navigation and report the difference.

## 5. Data Integrity and API Rules

-   The backend is the source of truth for marketplace data.
-   Listing content must originate from seller-submitted records
    returned through existing authorized endpoints.
-   Buyer visibility remains restricted to active listings according to
    the established backend rules.
-   Do not hardcode listing examples, prices, seller names, locations,
    ratings, review counts, or image URLs.
-   Do not invent API query parameters or endpoint capabilities.
-   Do not change database schema or backend behavior merely to
    reproduce the screenshot.
-   If required fields or capabilities are missing, document the gap and
    request approval before expanding the contract.
-   Preserve existing authentication, authorization, seller approval,
    and listing lifecycle rules.

## 6. Responsive Layout and Accessibility

-   Support Android devices with different widths and heights.
-   Make the Home content vertically scrollable.
-   Keep the bottom navigation from overlapping scrollable content.
-   Use responsive layouts for category tiles and listing cards.
-   Avoid horizontal overflow and clipped content.
-   Respect system text scaling and safe areas.
-   Use accessible labels for icon-only controls.
-   Keep adequate color contrast and touch targets.
-   Provide loading, empty, error, and missing-image states.

## 7. Flutter Architecture and Implementation

-   Inspect the current Home, Marketplace, BuyerShell, models,
    repositories, services, and controllers before editing.
-   Follow the existing feature-first architecture and state-management
    patterns.
-   Reuse existing API and state layers rather than duplicating them.
-   Reuse existing theme tokens and widgets.
-   Use installed icon dependencies; ask before adding a new dependency.
-   Keep the temporary logo easy to replace.
-   Do not modify backend endpoints, migrations, or database schema
    without explicit approval.
-   Do not implement unsupported notifications, favorites, messaging,
    transactions, or other features just because they appear in the
    reference.

## 8. Protected Project Areas

-   Do not change buyer/seller capability rules, authorization, or
    listing lifecycle.
-   Do not replace the existing `mobile/DESIGN.md` wholesale; merge this
    Home specification carefully if requested.
-   Do not modify root `AGENTS.md`, root `DESIGN.md`, or
    `frontend/src/index.css`.
-   Preserve all existing M5/M6 work, Docker performance fixes, mobile
    configuration, tests, and uncommitted changes.
-   Do not reset Git state, reset the database, or delete Docker
    volumes.
-   Do not stage, commit, or push without explicit user consent.

## 9. Acceptance Criteria

1.  The Home screen follows the latest reference hierarchy: header,
    search, hero, categories, featured listings, recent listings, and
    bottom navigation.
2.  The temporary AgroBenta logo is reused if present.
3.  All listing cards use real seller-submitted API data.
4.  No fake prices, seller details, ratings, review counts, or image
    URLs are introduced.
5.  Category labels/icons follow the approved taxonomy and use the
    existing icon system.
6.  Search, filters, CTAs, and navigation work only where supported.
7.  Unfinished destinations are not presented as functional.
8.  Loading, empty, error, and missing-image states are handled.
9.  `flutter analyze` and relevant tests pass.
10. Existing project changes remain intact.

## 10. Change and Validation Report

After implementation, report: - Files changed. - Assets and existing API
layers reused. - How seller-submitted listings populate the UI. - Which
fields/features are unavailable. - Any visual deviations caused by
missing assets or unfinished features. - Actual test results. -
Confirmation that no unrelated changes were overwritten and nothing was
staged, committed, or pushed.
