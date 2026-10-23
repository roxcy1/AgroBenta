# AgroBenta Mobile — Become a Seller Introduction Screen

## Purpose
Introduce the seller program and explain the benefits and verification requirement before the user begins the application. This is the first screen in the seller-verification flow.

## Layout
1. **Top navigation**
   - Back arrow on the left.
   - Title: `Become a Seller`.
   - Use the existing AgroBenta app bar and safe-area handling.
2. **Hero illustration**
   - Use the project's approved seller/livestock illustration asset if one exists.
   - Preserve aspect ratio and avoid stretching.
   - Do not download or invent a new branded asset without approval.
3. **Headline**
   - `Start Selling on AgroBenta`
4. **Supporting text**
   - Explain that sellers can list livestock and connect with interested buyers.
   - Do not promise sales, buyer volume, income, or guaranteed approval.
5. **Benefit cards**
   - `List your livestock` — create and manage supported listings.
   - `Get verified` — complete seller verification so eligible seller features can be enabled.
   - `Manage your listings` — maintain listings through supported workflows.
   - `Connect with buyers` — communicate through supported messaging functionality.
6. **Primary action**
   - Full-width green `Get Started` button with right-arrow icon.

## Behavior
- `Get Started` opens Step 1: Basic Information.
- Back returns to the previous screen.
- Do not create a seller capability or grant seller privileges when this page opens.
- Preserve the single-account approach: users apply using their existing account.

## Visual Design
- White/very light background, AgroBenta green accents, rounded pale-green benefit cards.
- Clear headline and concise body text.
- Existing theme typography and icon package; no emoji or arbitrary Unicode icons.
- Responsive layout and scroll support on small devices.

## Data and Security
- No sensitive documents are collected on this screen.
- Do not change user role or seller capability.
- Do not imply that starting an application means the user is verified.

## Acceptance Criteria
- Screen matches the supplied reference style.
- CTA opens the existing seller application flow.
- No seller privileges or backend state changes occur just by viewing this screen.
- Existing navigation and account state are preserved.
