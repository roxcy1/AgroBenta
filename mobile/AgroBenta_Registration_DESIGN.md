# AgroBenta Mobile UI Design --- Create Account Screen

## Purpose

This document specifies the visual design and interaction behavior for
the AgroBenta Flutter **Create Account** screen, based on the supplied
reference image. Treat the screenshot as the visual target while
preserving the existing application architecture, authentication API
contract, and mobile design system.

This is a screen-level specification. Review the existing
`mobile/DESIGN.md` before integrating it; do not replace that document
wholesale.

## 1. Visual Direction

-   **Brand:** AgroBenta --- a friendly, trustworthy livestock
    marketplace.
-   **Mood:** fresh, agricultural, welcoming, clean, and accessible.
-   **Primary color:** deep agricultural green, approximately `#08752F`
    to `#087A32`.
-   **Primary action:** rich green, approximately `#00752E`.
-   **Text:** near-black headings; dark slate labels and icons.
-   **Surface:** white form card with subtle light-gray borders.
-   **Background:** bright sky, soft clouds, rolling green hills, and
    cultivated countryside.
-   **Typography:** clean sans-serif, bold headings, legible field
    labels, and clear button text.
-   **Composition:** scenic branded header above a large white rounded
    registration panel.

Reuse existing theme and color constants where possible; do not create
duplicate theme systems without a clear need.

## 2. Screen Layout

### A. Scenic header

-   Fill the top portion with an agricultural landscape illustration or
    an existing approved project asset.
-   Include a light blue sky, soft clouds, green hills, trees, and a
    bright, optimistic atmosphere.
-   Place the project's actual AgroBenta logo centrally near the top. Do
    not redraw or substitute the brand mark.
-   Show **AgroBenta** in large, bold, dark green text.
-   Place the tagline below it: **"Buy. Sell. Grow. Together."**
-   Keep the header open and bright; ensure the logo and text remain
    readable.
-   Use an appropriate background fit such as `BoxFit.cover`, with the
    logo and text as separate widgets.
-   Prefer existing local assets and verify `pubspec.yaml` registration.
    Do not hardcode a network image URL.

### B. Registration card

-   Position a white card over the lower part of the scenic header,
    visually overlapping the landscape.
-   Use large rounded top corners (approximately 22--28 logical pixels).
-   Use horizontal padding of approximately 18--22 logical pixels.
-   Allow scrolling when the available height is insufficient; avoid
    fixed-height layouts that overflow on small devices or when the
    keyboard opens.
-   Heading: **"Create Your Account"**, centered, bold, near-black, and
    prominent.
-   Keep spacing consistent and uncluttered.

### C. Form fields

Use vertically stacked, full-width fields with rounded rectangular
outlines, white fill, and subtle light-gray borders. Target about 54--58
logical pixels in height on typical devices, with consistent vertical
spacing.

1.  **Full Name** --- leading person/profile outline icon; hint
    `Full Name`.
2.  **Email Address** --- leading envelope outline icon; hint
    `Email Address`; use email keyboard and appropriate autofill hints.
3.  **Password** --- leading lock outline icon; hint `Password`;
    trailing eye/eye-off button toggles visibility; secure entry by
    default.
4.  **Confirm Password** --- leading lock outline icon; hint
    `Confirm Password`; independent visibility toggle; validate that it
    matches the password.

Field behavior: - Provide clear labels or accessible semantics; do not
rely exclusively on hint text. - Show validation feedback close to the
relevant field. - Preserve field values after validation errors where
safe. - Never display raw stack traces or server internals. - Prevent
duplicate submissions while a request is in progress and show a clear
loading state. - Support screen readers and keyboard navigation.

## 3. Terms and Privacy Consent

-   Place a checkbox below the fields, unchecked by default.
-   Label: **"I agree to the Terms and Privacy Policy"**.
-   Render **Terms** and **Privacy Policy** as green, emphasized links.
-   Account creation must not proceed unless consent is checked if this
    is required by the existing registration requirements.
-   Only make links navigable if real destinations or approved pages
    exist. Do not invent URLs.
-   Keep the label tappable to toggle the checkbox while allowing the
    links to open independently.
-   Ensure clear selected state and accessible semantics.

## 4. Primary Action

-   Full-width green button labeled **"Create Account"**.
-   Rounded corners (approximately 10--12 logical pixels).
-   White, bold, centered label with comfortable padding.
-   Provide clear pressed and disabled states.
-   Display a loading indicator or progress state during submission.
-   Prevent multiple simultaneous registration requests.
-   Show validation and API errors without losing user input.
-   On success, follow the existing authentication/navigation flow; do
    not invent a new route.

## 5. Social Registration Area

-   Add a divider row with horizontal lines and centered text: **"or
    sign up with"**.
-   Display two outlined buttons side by side:
    -   Google logo and label **"Google"**.
    -   Facebook logo and label **"Facebook"**.
-   Use white backgrounds, light-gray borders, rounded corners, and dark
    labels.
-   Use official logo assets or existing approved assets; do not
    approximate official logos with unrelated icons.

**Functional requirement:** inspect the existing backend, authentication
contract, packages, and app configuration before wiring social sign-in.
If Google/Facebook authentication is not already supported, do not
create fake behavior, invent OAuth credentials, or imply that the
buttons work. Either render them clearly unavailable/disabled for this
iteration or omit them only after the project owner approves a deviation
from the reference design. Report the limitation.

## 6. Existing Account Link

At the bottom of the card, show centered text:

**"Already have an account? Log In"**

-   Use muted dark-gray text for the sentence.
-   Style **"Log In"** in green and with stronger weight.
-   Route to the existing login screen.
-   Do not create a duplicate login screen.

## 7. Responsive Behavior and Accessibility

-   Adapt to different screen sizes, including small Android phones.
-   Use a scrollable form or safe-area-aware layout so the keyboard does
    not permanently obscure fields or the primary action.
-   Respect system text scaling.
-   Ensure adequate contrast for hints, icons, borders, links, and
    button labels.
-   Provide semantic labels for icons and interactive controls.
-   Give password visibility controls meaningful accessibility labels.
-   Do not depend on iOS-only visual elements; the reference is visual
    inspiration, while the app must remain usable on supported Android
    devices.
-   Avoid horizontal overflow, clipped fields, and bottom overflow when
    the keyboard opens.

## 8. Flutter Implementation Guidance

-   Follow the existing feature-first and layered architecture.
-   Reuse the current authentication controller, repository, service,
    API client, validators, theme, and navigation patterns.
-   Inspect the existing registration implementation before making
    changes; improve it in place rather than creating a second
    authentication flow.
-   Keep widgets focused and reusable where that matches existing
    conventions.
-   Keep network and registration logic out of presentational widgets.
-   Use the existing API contract and request field names exactly.
-   Preserve server-side validation and authorization; client validation
    is not a substitute.
-   Do not add packages solely for visual styling unless necessary and
    approved.
-   Prefer existing local assets.
-   Do not modify backend endpoints or database schema merely to
    reproduce the screenshot.

## 9. Do Not Change

-   Do not change AgroBenta's core branding or actual logo.
-   Do not redesign unrelated screens.
-   Do not change buyer/seller capability rules, authorization, or API
    contracts.
-   Do not invent working social authentication if unsupported.
-   Do not add profile photo, address, or fields absent from the
    approved registration contract.
-   Do not overwrite existing `mobile/DESIGN.md`; merge this
    specification only if explicitly requested.
-   Do not change root `AGENTS.md` or root `DESIGN.md`.

## 10. Acceptance Criteria

The registration screen is accepted when:

1.  It follows the reference: agricultural hero, centered AgroBenta
    branding, overlapping white card, four fields, consent row, green
    CTA, social section, and login link.
2.  Password and confirmation visibility toggle independently.
3.  Required-field, email-format, password, confirmation, and consent
    validation follow existing approved registration requirements.
4.  API errors are clear, and successful registration follows the
    existing app flow.
5.  Duplicate submissions are prevented.
6.  The screen remains usable on small devices and while the keyboard is
    open.
7.  Social buttons do not falsely claim functionality unsupported by the
    backend.
8.  Existing authentication, marketplace, seller, and profile flows
    remain unaffected.
9.  `flutter analyze` and relevant Flutter tests pass.
10. No unrelated files or existing user changes are overwritten.
