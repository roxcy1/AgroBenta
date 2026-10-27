# AgroBenta Mobile UI Design --- Livestock Listing Details Screen

## Purpose

This specification describes the AgroBenta Flutter **Livestock Listing
Details** screen based on the supplied reference image.

The image is a visual design reference only. The displayed listing,
photo, price, location, animal attributes, description, seller identity,
and verification badge must be rendered from actual data returned by the
existing authorized API. Never hardcode the sample cattle listing or its
details.

## 1. Visual Direction

-   Dark agricultural-green top bar.
-   Large livestock photo carousel.
-   White details panel overlapping the lower edge of the photo.
-   Dark text, prominent green asking price, muted metadata.
-   Thin separators between detail groups.
-   Green outlined secondary action and filled green primary action.
-   Rounded corners and compact, readable spacing.
-   Use the existing app theme and icon package. Do not use emoji or
    arbitrary Unicode glyphs as icons.

## 2. Header and Image Gallery

### Header

-   Back arrow on the left.
-   Favorite/heart action on the right only if favorites are implemented
    and supported by API/state.
-   Use existing navigation behavior for back.
-   If favorites are not supported, omit the interactive heart or report
    it as unavailable; do not fake persistence.

### Listing image gallery

-   Display the real image(s) belonging to the selected listing, using
    image data/URLs supplied by the existing API.
-   Support multiple images with page indicators only when the API
    returns multiple images.
-   Do not synthesize image URLs, hardcode external image URLs, or reuse
    the reference photo as a fake listing.
-   If no photo exists, show a neutral branded placeholder.
-   Provide safe image-loading and image-error states.
-   Use a consistent, wide image area with a cover fit and rounded/clean
    edges.

## 3. Listing Summary Card

A white panel overlaps the lower portion of the image gallery.

Display only actual API fields: - Listing title/name. - Seller's asking
price, formatted using the existing currency formatter. - Location, only
if supplied by the approved API response.

Do not hardcode "Brown Cattle", ₱45,000, or "Trinidad, Bohol". Do not
infer missing fields from the photo or title.

## 4. Animal Attributes

Show a three-column attribute row with separators: - Age - Weight -
Gender

Render each attribute only when the current listing model/API supplies
it. Use existing canonical units and formatting: - Age: display the
API-provided value and supported unit. - Weight: display the
API-provided value and supported unit. - Gender: display the
API-provided value.

Do not fabricate attributes or use a default such as "2 years", "300
kg", or "Male" when values are missing. If a field is absent, use a
clear unavailable marker or omit that attribute according to the current
UI conventions. Do not add database fields or API properties without
approval.

## 5. Description

-   Section heading: **"Description"**.
-   Display the actual listing description returned by the API.
-   Preserve readable line spacing and allow long descriptions to scroll
    naturally.
-   Do not hardcode the sample text "Healthy and ready for breeding.
    Complete vaccination."
-   If the description is missing, show a neutral empty-state message or
    omit the section.

## 6. Seller Section

-   Section heading: **"Seller"**.
-   Display the seller name only if exposed by the approved mobile
    listing resource.
-   Display a real profile image only if the API provides a supported
    image field; otherwise use the existing generic avatar.
-   Display a "Verified Seller" badge only when verification status is
    explicitly approved by the backend and included in the authorized
    response.
-   Do not infer verification from seller capability, a name, or listing
    status alone.
-   Never expose seller email, private identifiers, or other data not
    intended for marketplace display.
-   Do not hardcode the screenshot's sample seller name, portrait, or
    verification badge.

## 7. Bottom Actions

Two side-by-side buttons: - **Message** --- outlined green button with
message icon. - **Inquire** --- filled green button with a list/document
icon.

### Message

-   Navigate to or invoke the existing messaging feature only if
    implemented and approved.
-   Do not invent messaging endpoints or create a fake conversation.
-   If messaging is not available in the current phase, omit/disable the
    action according to existing conventions and report the gap.

### Inquire

-   Inspect the existing transaction/inquiry contract before
    implementing.
-   Do not assume that an inquiry creates a transaction, reserves an
    animal, sends a message, or changes listing status.
-   If a supported inquiry flow exists, use it.
-   If not implemented, ask for approval or show the action as
    unavailable; do not invent an endpoint or database write.

Keep the action area clear of system gesture navigation and scrollable
content. Use safe-area padding.

## 8. Data and API Rules

-   Reuse the existing Browse/Marketplace listing detail route, listing
    model, repository, service, and controller.
-   Load details using the selected listing ID and existing authorized
    API endpoint.
-   Do not hardcode sample listing data or images.
-   Buyer-visible listings must obey existing active-listing visibility
    rules; hidden/inactive listings must not be exposed through a new
    client-side path.
-   Do not synthesize photo URLs or infer missing attributes.
-   Do not change backend endpoints, response resources, migrations, or
    schema without explicit approval.
-   Preserve seller verification, authentication, and listing lifecycle
    rules.

## 9. Responsive and Accessibility Requirements

-   Support different Android screen sizes.
-   Allow the details content to scroll vertically.
-   Keep the bottom actions accessible without obscuring the
    description.
-   Respect safe areas and system text scaling.
-   Provide accessible labels for icon-only actions and image
    indicators.
-   Maintain adequate contrast and touch targets.
-   Handle loading, not-found, authorization, network-error, and
    image-error states consistently with the existing app.

## 10. Flutter Implementation Guidance

-   Inspect the existing listing detail screen, listing model,
    marketplace service/repository/controller, navigation, and tests
    before editing.
-   Reuse existing feature-first architecture and API layers.
-   Use installed icon dependencies and existing theme tokens.
-   Avoid duplicate network services or duplicate detail screens.
-   Do not add dependencies unless needed and approved.
-   Do not modify backend APIs or database schema solely to match the
    screenshot.

## 11. Protected Areas and Git Rules

-   Preserve all existing M5/M6 work, Browse/filter work, Docker fixes,
    mobile configuration, tests, and uncommitted modifications.
-   Do not modify `frontend/src/index.css`, root `AGENTS.md`, or root
    `DESIGN.md`.
-   Do not reset, clean, revert, or discard Git changes.
-   Do not reset the database or delete Docker volumes.
-   Do not stage, commit, or push to GitHub without explicit user
    consent.

## 12. Acceptance Criteria

1.  Listing details visually follow the reference hierarchy: image
    gallery, title, price, location, attributes, description, seller,
    and bottom actions.
2.  All listing content comes from the actual selected listing API
    response.
3.  Multiple image indicators appear only when multiple real images
    exist.
4.  Missing attributes and images are handled safely without fabricated
    values.
5.  Seller verification is shown only when backed by authorized backend
    data.
6.  Favorite, Message, and Inquire actions are functional only if
    supported; otherwise they are omitted/disabled and reported.
7.  Existing active-listing visibility and authorization rules remain
    intact.
8.  `flutter analyze` and relevant listing-detail tests pass.
9.  Existing project changes are preserved; nothing is staged,
    committed, or pushed.

## 13. Final Report

Report files changed, API fields/assets reused, unsupported
attributes/actions, actual test results, and confirmation that unrelated
changes were preserved and nothing was staged, committed, or pushed.
