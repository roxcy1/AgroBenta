# AgroBenta Mobile UI Design --- Login Screen

## Purpose

This document specifies the AgroBenta Flutter **Login** screen based on
the supplied reference image. Use the image as the visual target while
preserving the existing authentication flow, API contract, app
architecture, and shared visual design.

This is a screen-specific specification. Review `mobile/DESIGN.md` and
the existing registration screen design before integrating shared
tokens. Do not replace either document wholesale.

## 1. Visual Direction

-   **Brand:** AgroBenta --- a trustworthy, approachable livestock
    marketplace.
-   **Mood:** fresh, rural, optimistic, professional, and welcoming.
-   **Primary green:** approximately `#08752F`--`#087A32`.
-   **Primary button:** rich green, approximately `#00752E`.
-   **Text:** near-black headings, dark slate body text.
-   **Surface:** white card and white inputs with subtle cool-gray
    borders.
-   **Hero:** bright agricultural landscape with hills, grazing
    livestock, soft clouds, and daylight.
-   **Typography:** clean sans-serif with bold brand/title text and
    readable supporting labels.
-   **Composition:** branded landscape header with a white login card
    overlapping its lower edge.

Reuse existing app theme values and components where possible.

## 2. Layout and Header

### A. Safe area and screen sizing

-   Respect device safe areas and status bar.
-   Adapt to common Android phone sizes.
-   Allow the page to scroll when height is limited or the keyboard
    opens.
-   Avoid fixed heights that cause overflow.

### B. Agricultural hero

-   Use a bright landscape illustration or existing approved local asset
    with rolling green hills, a grassy field, and livestock such as
    sheep and cattle.
-   Keep the landscape bright and calm, with soft clouds and distant
    green hills.
-   Use the existing official AgroBenta logo asset centered near the
    upper part of the hero.
-   Display **AgroBenta** in large, bold, dark-green text.
-   Display the tagline **"Buy. Sell. Grow. Together."** beneath the
    wordmark.
-   Ensure text and logo contrast with the background.
-   Prefer existing local assets; verify asset declarations in
    `pubspec.yaml`.
-   Do not hardcode remote image URLs or invent a replacement logo.

### C. Overlapping login panel

-   Place a white panel over the lower part of the hero.
-   Use rounded upper corners, approximately 20--26 logical pixels.
-   Keep consistent horizontal padding, approximately 16--20 logical
    pixels.
-   The card should visually join the hero while remaining scrollable.
-   Avoid shadows or gradients that are stronger than the reference.

## 3. Heading

Inside the card, center the following:

-   Heading: **"Welcome Back!"** --- bold, near-black, prominent.
-   Supporting text: **"Sign in to continue"** --- smaller, muted dark
    gray.

Use adequate spacing without making the form unnecessarily tall.

## 4. Login Form

Use two full-width, outlined fields with white fill, subtle cool-gray
borders, and rounded corners. Target approximately 50--56 logical pixels
in height, subject to existing shared components.

### A. Email Address

-   Leading envelope/mail icon.
-   Hint text: `Email Address`.
-   Email keyboard and appropriate autofill hints.
-   Trim unintended surrounding whitespace if consistent with existing
    auth behavior.

### B. Password

-   Leading lock icon.
-   Hint text: `Password`.
-   Trailing eye/eye-off control for showing or hiding the password.
-   Hidden by default.
-   Provide a semantic accessibility label for the visibility control.
-   Use password autofill hints.

### Form behavior

-   Preserve existing request field names and authentication API
    behavior.
-   Validate required fields using existing conventions.
-   Show readable validation and authentication errors.
-   Do not reveal whether a particular account exists beyond the
    existing backend's behavior.
-   Prevent duplicate submissions and show a loading state while the
    login request is active.
-   Avoid exposing raw exceptions, stack traces, tokens, or server
    details.
-   Ensure keyboard navigation and screen-reader semantics.

## 5. Remember Me and Forgot Password

Display a single horizontal row beneath the fields:

### Remember me

-   Green checkbox, checked by default only if that matches the existing
    approved behavior; otherwise use the existing default.
-   Label: **"Remember me"**.
-   Do not add persistent token storage or change session lifetime just
    to match the visual reference.
-   Inspect the existing authentication behavior. If a remember-me
    feature is not supported, do not falsely imply that the checkbox
    changes authentication persistence. Ask for approval or clearly
    disable/omit the control and report the difference.

### Forgot Password?

-   Right-aligned green text: **"Forgot Password?"**
-   Navigate only to an existing, supported password recovery flow.
-   Do not invent an endpoint, reset-token process, or destination.
-   If password recovery is not implemented, report this limitation and
    leave the link unavailable/disabled unless the project owner
    approves a separate recovery feature.

Keep both controls readable on narrow devices; allow wrapping if needed
rather than overflowing.

## 6. Primary Login Button

-   Full-width green button labeled **"Log In"**.
-   White bold text, rounded corners (approximately 9--12 logical
    pixels).
-   Comfortable touch height.
-   Provide pressed, disabled, and loading states.
-   Disable repeat submissions while a request is in progress.
-   On success, follow the existing authentication gate and navigation
    flow.
-   On failure, show a clear, safe message using existing API error
    handling.

## 7. Social Login Section

-   Add a horizontal divider with centered text: **"or continue with"**.
-   Display two side-by-side outlined buttons:
    -   Google logo.
    -   Facebook logo.
-   In the reference, the social buttons are primarily logo-centered.
-   Use official logo assets or existing approved assets. Do not
    approximate official logos with unrelated icons.

**Functional requirement:** inspect existing OAuth support before
enabling social login. If Google/Facebook authentication is unsupported,
do not invent credentials, endpoints, or fake success behavior. Render
the buttons as clearly unavailable/disabled or ask for approval to omit
them, and report the limitation.

## 8. Registration Link

At the bottom, center:

**"Don't have an account? Sign Up"**

-   Use dark muted text for the sentence.
-   Style **"Sign Up"** in green and stronger weight.
-   Navigate to the existing registration screen.
-   Do not create a duplicate registration flow.

## 9. Shared Design Consistency

The login and registration screens should feel like one cohesive
authentication experience: - Same AgroBenta logo and wordmark
treatment. - Same landscape art style and color palette. - Matching
input border, radius, icon color, and typography. - Matching green
primary button. - Matching white overlapping card style. - Matching link
color and spacing rhythm.

The screens may differ in content and vertical spacing to suit their
fields. Do not force identical fixed heights.

## 10. Flutter Implementation Guidance

-   Inspect and update the existing login screen rather than creating a
    second screen.
-   Reuse the existing auth controller, repository, service, API client,
    theme, and navigation.
-   Keep network calls and authentication logic out of presentational
    widgets.
-   Use existing API request fields and token handling.
-   Reuse existing shared form-field and button components where
    suitable.
-   Prefer existing local assets and dependencies.
-   Do not change backend endpoints, database schema, token abilities,
    or authentication rules to match the visual reference.
-   Do not add packages solely for visual styling without a clear need
    and approval.

## 11. Do Not Change

-   Do not replace the actual AgroBenta logo.
-   Do not redesign unrelated screens.
-   Do not change buyer/seller capability rules or authorization.
-   Do not invent password reset or social-login functionality.
-   Do not introduce new persistent "remember me" behavior unless it is
    already supported or separately approved.
-   Do not overwrite `mobile/DESIGN.md` or the registration-specific
    design file.
-   Do not modify root `AGENTS.md`, root `DESIGN.md`, or
    `frontend/src/index.css`.

## 12. Acceptance Criteria

The login screen is accepted when:

1.  The visual structure follows the reference: agricultural hero,
    centered branding, overlapping white card, welcome heading,
    email/password fields, remember-me/forgot-password row, green login
    button, social section, and sign-up link.
2.  Password visibility toggles correctly.
3.  Login uses the existing backend authentication contract.
4.  Loading, validation, and authentication errors are handled clearly.
5.  Unsupported remember-me, forgot-password, and social-login features
    are not represented as functional.
6.  The screen remains usable on small devices and with the keyboard
    open.
7.  The existing registration flow remains connected.
8.  Existing auth, marketplace, seller, and profile features are
    unaffected.
9.  `flutter analyze` and relevant tests pass.
10. Existing user changes are preserved.
