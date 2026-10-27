# AgroBenta Mobile UI Design --- Profile Screen

## Purpose

This specification defines the AgroBenta Flutter **Profile** screen
based on the supplied reference image. The screenshot is a visual
target, not permission to add unsupported backend fields or features.
Render only information available from the authenticated user's existing
API response or other approved APIs. Do not invent profile data,
delivery addresses, notification preferences, or account statuses.

## 1. Visual Direction

-   Brand: AgroBenta, a welcoming and trustworthy livestock marketplace.
-   Primary green: reuse the existing app theme.
-   Secondary surfaces: pale green for Buyer Mode and pale amber for
    Become a Seller.
-   Background: white or very light neutral.
-   Cards: white with rounded corners and restrained borders/shadows.
-   Text: high-contrast headings and muted gray descriptions.
-   Icons: use the existing icon package and shared icon components, not
    emoji or arbitrary Unicode glyphs.
-   Compact settings rows with consistent spacing and accessible tap
    targets. Reuse existing theme tokens and shared components. Do not
    introduce a second design system.

## 2. Screen Structure

### A. Branded Header

-   Display the temporary AgroBenta logo and wordmark over an
    agricultural landscape banner if approved local assets already
    exist.
-   Use the tagline **"Buy. Sell. Grow. Together."** if it fits.
-   Prefer existing local assets. Do not hardcode remote image URLs or
    invent a new logo.
-   If no suitable landscape asset exists, use a restrained
    green/pale-green placeholder and report the missing asset.
-   Respect the device safe area.

### B. Profile Summary Card

A white card overlaps the lower edge of the header.

Show only fields available from the authenticated profile/API
response: - Actual user name. - Actual user email. - Location only if it
exists in the approved response. - Profile image only if an approved
field and asset/URL exist; otherwise use the existing generic avatar.

The screenshot's sample name, email, location, and portrait are
illustrative only. Do not hardcode them.

Provide an edit action only for fields supported by the current M6
profile implementation. Name editing is supported; email editing remains
deferred. Do not expose email editing or add profile-image upload
without approval. If avatar capture/upload is unsupported, do not show a
working camera action.

### C. Account Mode Card

-   Pale-green rounded card with a cart icon.
-   Heading: **"Account Mode"**.
-   Display the user's actual current buyer/seller capability using
    existing API/user model data.
-   Show status such as Active only when supported by real server state.
-   Do not create a separate seller account or client-side mode switch.
-   Never allow the client to change `role` or `seller_capability`; the
    backend remains authoritative.
-   If a dropdown has no approved behavior, omit it.

### D. Become a Seller Card

-   Pale amber/yellow rounded card.
-   Person-plus icon and heading: **"Become a Seller"**.
-   Supporting text: **"Complete seller verification to start selling
    livestock."**
-   Use a decorative livestock illustration only if an approved local
    asset exists.
-   Navigate to the existing seller-verification flow.
-   If already approved as a seller, follow the existing status
    behavior.
-   Do not create a separate seller account or bypass server-side
    verification.

### E. Account Settings

Use a white rounded panel with separated tappable rows, each with
leading icon, title, description, and trailing chevron.

Reference rows: 1. **Personal Information** --- "View and update your
personal details" 2. **Address** --- "Manage your delivery address" 3.
**Change Password** --- "Update your account password" 4. **Notification
Settings** --- "Manage your notification preferences"

Feature rules: - Personal Information: connect to existing M6 profile
and name-edit flow. - Address: only navigate to an implemented, approved
feature. The current known profile contract has no address field; do not
add fields, migrations, or fake persistence. - Change Password: connect
to the existing M6 password-change screen. - Notification Settings: only
use an existing preferences feature backed by supported APIs/state. - If
a feature is not implemented, do not make it appear functional. Omit it
or clearly mark it unavailable according to existing conventions, and
report the limitation.

### F. Other

Reference rows: 1. **Help and Support** --- "Get help or contact
support" 2. **Terms and Policies** --- "View our terms, privacy policy,
and guidelines" 3. **Log Out** --- "Sign out from your account"

Rules: - Help and Support must open an existing support destination or
approved contact method; do not invent contact details. - Terms and
Policies must open approved content or configured destinations; do not
invent URLs. - Log Out must use the existing authentication
controller/service and logout flow. - After logout, follow the existing
authentication gate. - Never expose tokens or sensitive data in UI/logs.

## 3. Bottom Navigation --- Required Order

Use this exact visible order: 1. **Home** 2. **Browse** 3. **Messages**
4. **Transactions** 5. **Profile**

-   Rename Marketplace to **Browse** if not already done.
-   Profile is selected on this screen.
-   Reuse existing destinations and route state.
-   Do not add placeholder tabs that lead nowhere. If Messages or
    Transactions are not implemented, report the gap and ask before
    adding nonfunctional destinations.
-   Use the existing icon package, consistent selected/unselected
    styling, accessible labels, and comfortable tap targets.

## 4. Data, API, and Security Rules

-   The authenticated API is the source of truth for profile details and
    account capability.
-   Do not hardcode the screenshot's sample identity, email, address, or
    profile image.
-   Do not invent address or notification-preference fields.
-   Do not allow mobile users to modify `role` or `seller_capability`.
-   Reuse existing profile, auth, seller-verification, and logout
    layers.
-   Do not add endpoints, schema columns, migrations, or dependencies
    without approval.
-   Email editing remains deferred; keep it read-only under the current
    M6 scope.
-   Profile image upload remains out of scope unless separately
    approved.

## 5. Responsive and Accessibility

-   Support different Android screen sizes.
-   Use a scrollable page so all settings remain accessible.
-   Respect safe areas and system text scaling.
-   Avoid bottom-navigation overlap.
-   Provide accessible labels for icon-only actions.
-   Maintain adequate contrast and touch targets.
-   Show loading, error, and unavailable states consistently with the
    existing app.

## 6. Flutter Implementation Guidance

-   Inspect the existing Profile screen, M6 profile
    state/controller/repository/service, seller-verification flow,
    BuyerShell, auth controller, and tests before editing.
-   Reuse existing layers and navigation; do not create a duplicate
    profile implementation.
-   Use existing theme tokens and icon dependencies.
-   Keep local asset usage centralized.
-   Do not modify backend APIs or schema solely to reproduce the
    screenshot.

## 7. Protected Areas and Git Rules

-   Preserve all existing M5/M6 work, Docker changes, mobile
    configuration, tests, and uncommitted changes.
-   Do not modify `frontend/src/index.css`, root `AGENTS.md`, or root
    `DESIGN.md`.
-   Do not reset, clean, revert, or discard Git changes.
-   Do not reset the database or delete Docker volumes.
-   Do not stage, commit, or push to GitHub without explicit user
    consent.

## 8. Acceptance Criteria

1.  Profile follows the reference: branded header, profile summary,
    account-mode card, Become a Seller card, Account Settings, Other,
    and bottom navigation.
2.  Identity comes from the authenticated API response.
3.  The existing temporary AgroBenta logo is reused if available.
4.  Personal Information and Change Password connect to the existing M6
    implementation.
5.  Seller verification uses the existing server-controlled flow.
6.  Address, notification settings, help, and terms are not presented as
    functional unless supported destinations exist.
7.  Email remains read-only and no profile-image upload is invented.
8.  Bottom navigation order is Home, Browse, Messages, Transactions,
    Profile.
9.  `flutter analyze` and relevant Profile/navigation tests pass.
10. Existing changes are preserved; nothing is staged, committed, or
    pushed.

## 9. Final Report

Report files changed, existing profile/auth/seller-verification layers
reused, which rows are functional/unavailable/deferred, missing
assets/backend fields, actual test results, and confirmation that
unrelated changes were preserved and nothing was staged, committed, or
pushed.
