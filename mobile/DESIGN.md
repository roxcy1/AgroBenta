# AgroBenta Mobile — DESIGN.md

## 1. Purpose

This document defines the visual and interaction design standards for the **AgroBenta Mobile Application** based on the approved mobile prototype.

The mobile application follows the **Single Account Approach**:

- Every registered user starts as a buyer.
- A user may choose **Become a Seller**.
- Seller functionality becomes available only after seller verification and approval.
- Buyer and seller capabilities remain under the same account.
- The mobile application serves both **Buyer** and **Seller** experiences.

The design target is a clean, modern, trustworthy agricultural marketplace that is easy to use on Android phones and remains practical for users with different levels of technical familiarity.

---

# 2. Design Direction

## 2.1 Overall Visual Style

AgroBenta uses a:

- Clean agricultural marketplace aesthetic
- Professional but approachable appearance
- Green-focused visual identity
- White content surfaces
- Rounded cards and form controls
- Compact mobile layouts
- Clear hierarchy
- Minimal decorative elements
- Strong use of livestock photography
- Simple icons instead of text-heavy controls
- Clear status indicators
- Consistent bottom navigation

The interface should feel like a **real livestock marketplace application**, not a generic AI or banking application.

### Design Principles

1. **Clarity first**
   - Users should immediately understand what they can do on each screen.
   - Avoid unnecessary decorative elements.

2. **Agricultural identity**
   - Use green as the primary brand color.
   - Livestock photos should be prominent where appropriate.

3. **Trust**
   - Verification, seller status, transaction status, and system feedback must be visually clear.

4. **Simple interaction**
   - Use familiar controls such as search fields, chips, dropdowns, sliders, cards, buttons, and bottom navigation.

5. **Consistent hierarchy**
   - Screen title → supporting information → content → primary action.

6. **Mobile-first**
   - Designs must work comfortably on small Android screens.
   - Avoid layouts that depend on large desktop dimensions.

---

# 3. Color System

The prototype uses a dark agricultural green as the dominant brand color with white content surfaces and lighter green accents.

The following values are the implementation target and may be adjusted slightly if the existing AgroBenta branding requires exact matching.

| Purpose | Color | Hex |
|---|---|---|
| Primary brand | Dark agricultural green | `#006B4F` |
| Primary action | Marketplace green | `#008A5A` |
| Dark header | Deep green | `#005A43` |
| Light green surface | Very light green | `#EAF7F0` |
| Success | Green | `#168A4A` |
| Warning | Amber | `#D98B00` |
| Error | Red | `#C93636` |
| Text primary | Near black | `#202124` |
| Text secondary | Gray | `#6B7280` |
| Border | Light gray | `#D9DEE3` |
| Page background | Very light gray | `#F7F8F7` |
| Card background | White | `#FFFFFF` |

### Color Usage

- Primary green is reserved for:
  - App bars
  - Primary buttons
  - Selected navigation
  - Important actions
  - Verification/success indicators where appropriate

- White is used for:
  - Main content surfaces
  - Cards
  - Forms
  - Bottom navigation

- Light green is used for:
  - Information panels
  - Selected/active surfaces
  - Seller-related highlights
  - AI suggestion result backgrounds

- Red and amber are used only for meaningful status conditions.

Do not use gradients, neon colors, excessive shadows, or decorative color effects.

---

# 4. Typography

Use the platform/system font unless the project already contains an approved AgroBenta font.

Recommended hierarchy:

| Element | Weight | Approx. Size |
|---|---:|---:|
| Screen title | Bold | 18–20sp |
| Section heading | Semi-bold | 15–17sp |
| Card title | Semi-bold | 14–16sp |
| Body text | Regular | 13–15sp |
| Secondary text | Regular | 11–13sp |
| Button label | Semi-bold | 13–15sp |
| Price | Bold | 15–18sp |
| Small status text | Medium | 10–12sp |

### Typography Rules

- Use sentence case for normal UI text.
- Avoid excessive ALL CAPS.
- Keep labels short.
- Prices should be visually prominent.
- Supporting information should be lighter than the primary content.
- Do not use oversized headings that consume most of the screen.

---

# 5. Spacing

Use a consistent 4/8-point spacing system.

Recommended values:

```text
4dp   — very small spacing
8dp   — icon/text spacing
12dp  — compact component spacing
16dp  — standard screen padding
20dp  — section separation
24dp  — major section separation
32dp  — large visual separation
```

### Screen Padding

Default horizontal screen padding:

```text
16dp
```

Cards may use:

```text
12dp–16dp internal padding
```

Avoid tightly packed controls.

---

# 6. Shape and Radius

The prototype uses rounded controls and cards without excessive pill styling.

Recommended:

```text
Text fields:      8–10dp
Cards:            10–12dp
Primary buttons:  8–10dp
Dialogs:          12–16dp
Chips:             8–16dp
Image containers: 10–12dp
```

Avoid making every component fully pill-shaped.

Pill shapes should primarily be used for:

- Filter chips
- Status chips
- Compact category selectors

---

# 7. Elevation and Borders

Use subtle elevation.

Recommended:

```text
Cards: 1–2dp elevation
Dialogs: 4–8dp elevation
Bottom navigation: subtle elevation
```

Borders may be used for:

- Form fields
- Filter controls
- Unselected cards
- Secondary buttons

Do not use heavy shadows.

---

# 8. App Structure

The mobile application follows the following navigation model:

```text
AgroBenta
│
├── Authentication
│   ├── Register
│   └── Login
│
├── Buyer
│   ├── Home
│   ├── Browse Livestock
│   ├── Search
│   ├── Filters
│   ├── Livestock Details
│   ├── Messages
│   ├── Notifications
│   └── Profile
│
└── Seller Capability
    ├── Become a Seller
    ├── Seller Information
    ├── Verification
    ├── Submit Seller Verification
    ├── My Listings
    ├── Create Listing
    └── AI Price Suggestion
```

Seller features must not appear as active seller-management features until the account is approved.

---

# 9. Bottom Navigation

The prototype uses a five-item mobile navigation pattern.

Recommended structure:

```text
Home
Browse
Sell / Seller
Notifications
Profile
```

The exact label for the third item may adapt to account state.

### Buyer State

The user can see:

```text
Home
Browse
Become a Seller
Notifications
Profile
```

### Approved Seller State

Seller-related entry points become available through the seller experience.

The navigation must remain simple and should not introduce a separate seller account.

---

# 10. App Bar

App bars use the AgroBenta green brand color.

Typical structure:

```text
←   Screen Title                         Action
```

Examples:

```text
← Browse Livestock
← Filter Livestock
← Livestock Details
← Seller Verification
← Create Listing
```

Rules:

- Use a back arrow for child screens.
- Keep titles short.
- Use right-side icons only when the action is useful.
- Do not overcrowd the app bar.

---

# 11. Authentication Screens

## 11.1 Register

The prototype shows a simple registration form.

Recommended structure:

```text
              AgroBenta Logo

              AgroBenta
        Buy. Sell. Grow. Together.

Full Name
Email Address
Password
Confirm Password

☑ I agree to the Terms and Privacy Policy

[ Create Account ]

Already have an account? Log in
```

### Rules

- Primary action uses the AgroBenta green.
- Validation appears near the affected field.
- Password fields must use secure input.
- Terms and privacy acknowledgement must be clear.
- Do not introduce seller selection during registration.

---

# 12. Login Screen

Structure:

```text
              AgroBenta Logo

              Welcome Back!

Email Address
Password

☑ Remember me          Forgot Password?

[ Log In ]

or continue with

[ Google ] [ Facebook ]

Don't have an account? Sign Up
```

The actual authentication options must follow the implemented backend capabilities.

Do not visually imply that social login works if it is not implemented.

---

# 13. Home Screen

The prototype home screen is buyer-oriented.

Recommended hierarchy:

```text
Hello, Juan!
Happy trading!

[ Search livestock... ]

Category shortcuts

[Cattle] [Swine] [Goat] [Carabao]

Quality Livestock,
Better Opportunities.

Featured Listings
────────────────────
Livestock Card
Livestock Card
```

### Home Screen Rules

- Greeting is personalized using the authenticated user's name.
- Search should be immediately visible.
- Category shortcuts provide fast access.
- Featured listings use real listing data.
- Avoid overcrowding the home screen.

---

# 14. Livestock Cards

Livestock cards are one of the most important reusable components.

Recommended structure:

```text
┌──────────────────────────────┐
│        Livestock Image       │
│                              │
├──────────────────────────────┤
│ Brown Cattle             ♡   │
│ ₱45,000                     │
│ 📍 San Isidro, Nueva Ecija  │
│                              │
│ Native   2 years   350 kg   │
└──────────────────────────────┘
```

### Card Information

Where available:

- Livestock image
- Livestock type
- Breed
- Price
- Location
- Age
- Weight
- Gender
- Favorite action

Do not display sensitive seller information such as seller email on marketplace cards.

---

# 15. Browse Livestock

The browse screen should emphasize search and discovery.

Structure:

```text
Browse Livestock

[ Search livestock... ]

[All] [Cattle] [Swine] [Goat] [Carabao]

Livestock cards
```

### Search

Search should be:

- Easy to locate
- Fast to use
- Clearable
- Server-backed

When searching, preserve the user's existing marketplace context.

---

# 16. Filters

The prototype uses a dedicated filter screen.

Recommended filters:

```text
Livestock Type
[ Cattle ▼ ]

Price
₱0 ───────── ₱100,000

Location
[ Select Location ▼ ]

Age
[ Any ▼ ]

Gender
[ Any ▼ ]

Sort By
[ Most Recent ▼ ]

[ Apply Filters ]

[ Reset ]
```

### Filter Rules

- Filters must have clear labels.
- Selected values should remain visible.
- Reset must restore default values.
- Apply Filters should be the primary action.
- Avoid excessive filter controls on the initial browse screen.

---

# 17. Livestock Details

Structure:

```text
[ Large Livestock Image ]

Brown Cattle
₱45,000

📍 San Isidro, Nueva Ecija

Native
2 years
350 kg
Male

Description
Healthy and ready for breeding.
Complete vaccination.

Seller
[Profile] Juan Dela Cruz
✓ Verified Seller

[ Message ] [ Inquire ]
```

### Important

Seller information must clearly communicate verification status when applicable.

The buyer must be able to understand:

- What livestock is being offered
- Price
- Location
- Basic livestock information
- Seller information
- Available actions

---

# 18. Profile

The prototype uses a single-account profile.

Structure:

```text
[ Profile Photo ]

Juan Dela Cruz
juandc@gmail.com

[ Edit ]

Personal Information          >
Address                       >
Change Password               >
Notification Settings         >

Seller Account
Not yet a seller?

[ Become a Seller ]
```

For an approved seller:

```text
Seller Account
✓ Verified Seller

[ Manage Listings ]
```

There must be no separate seller login.

---

# 19. Become a Seller

This screen explains the seller capability before verification.

Recommended structure:

```text
Become a Seller

        [Seller Illustration]

Start selling your livestock
on AgroBenta!

✓ Create livestock listings
✓ Get AI-based price suggestions
✓ Reach more buyers
✓ Build your trusted seller profile

[ Start Seller Verification ]
```

The content should be concise and benefit-oriented.

---

# 20. Seller Verification

The seller verification flow uses clear stages.

Recommended progress indicator:

```text
① Information
      ↓
② Documents
      ↓
③ Review
```

### Verification States

The UI must clearly represent:

```text
Submitted
Pending Review
Approved
Rejected
```

### Approved

Use a prominent success indicator:

```text
✓

Verified Seller

This seller has completed the
verification process and is now
a trusted seller on AgroBenta.
```

### Rejected

Show:

- Verification status
- Admin-provided reason/note when available
- Resubmission action

Do not imply approval before the server actually confirms it.

---

# 21. Seller Information

The seller information screen displays the authenticated user's seller-related information.

Recommended structure:

```text
[Profile]

Juan Dela Cruz
✓ Verified Seller

Location
San Isidro, Nueva Ecija

Seller since
January 2024

Listings
12 active listings

Rating
4.8 (24 reviews)

[ View Listings ]

[ Message ]
```

Only display information that is actually available from the system.

---

# 22. Create Livestock Listing

The prototype uses a step-based form.

Recommended flow:

```text
Create Listing

① Information
② Details
③ Review
```

Form:

```text
Upload Photos
[ + ]

Livestock Type
[ Cattle ▼ ]

Breed
[ Native ▼ ]

Age
[ 2 years ]

Weight
[ 350 kg ]

[ Next ]
```

### Listing Rules

- Seller identity is derived from the authenticated account.
- Seller must not enter or select another seller account.
- Status must be controlled by the system.
- Required fields must be clearly identified.
- Photo upload UI may be shown only when the implemented storage/upload capability is available.

---

# 23. My Listings

The prototype uses status tabs:

```text
[Active] [Pending] [Sold] [Drafts]
```

Listing card:

```text
Brown Cattle
₱45,000

[ Edit ] [ Pause ]
```

### Status Meaning

```text
Draft
Private and incomplete.

Pending
Submitted and awaiting admin review.

Active
Approved and visible to buyers.

Sold
No longer available.

Inactive
Temporarily unavailable.
```

Seller must not directly change a listing from pending to active.

---

# 24. AI Price Suggestion

AI price suggestion is presented as **decision support**, not automatic pricing.

Input screen:

```text
AI Price Suggestion

Get an estimated market price for
your livestock listing.

Livestock Type
[ Cattle ]

Breed
[ Native ]

Age
[ 2 years ]

Weight
[ 350 kg ]

[ Get Suggestion ]
```

Result:

```text
Estimated Price Range

₱40,000 – ₱50,000

Based on market trends,
breed, age, weight, and
recent listings.

Confidence Level

High (65%)

[ Use This Price ]
```

### Important Design Rule

The suggested price must never appear to automatically become the seller's final asking price.

The seller remains responsible for the final asking price.

---

# 25. Messages

The prototype uses a simple conversation list.

Structure:

```text
Messages

Juan Santos
Interested in your cattle.
10:50 AM

Pedro Reyes
Available po?
Yesterday

Ana Cruz
Thank you!
Jan 10
```

Rules:

- Show conversation preview.
- Show timestamp.
- Unread messages may use stronger typography.
- Keep message lists compact.

---

# 26. Transactions

Transaction status is represented through tabs/chips.

Recommended:

```text
[Ongoing] [Completed] [Cancelled]
```

Transaction card:

```text
TRX-001

Brown Cattle
₱45,000

Ongoing
```

Status colors:

- Ongoing → green/neutral
- Completed → success green
- Cancelled → red

Use status colors consistently throughout the application.

---

# 27. Notifications

Notifications use a chronological list.

Examples:

```text
✓ Your verification has been approved.
  2 hours ago

● New message from Maria Santos
  4 hours ago

✓ Your listing has been viewed.
  1 day ago

✓ Transaction completed
  2 days ago
```

Rules:

- Unread notifications should be visually distinguishable.
- Notification icons should communicate category.
- Keep notification titles concise.

---

# 28. Buttons

## Primary Button

Use for the main action:

```text
[ Create Account ]
[ Log In ]
[ Apply Filters ]
[ Submit ]
[ Create New Listing ]
[ Get Suggestion ]
```

Characteristics:

- AgroBenta green background
- White text
- Medium weight
- 8–10dp radius
- Minimum comfortable touch target

## Secondary Button

Use for secondary actions:

```text
[ Cancel ]
[ Reset ]
[ Edit ]
```

Prefer outlined or light-surface treatment.

## Destructive Button

Use only for destructive actions.

Examples:

```text
Delete Listing
Cancel Transaction
```

Use the error color sparingly.

---

# 29. Form Fields

Form fields should have:

```text
Label
[ Input / Selection ]
Optional helper or error text
```

Examples:

```text
Livestock Type
[ Cattle                         ▼ ]

Weight
[ 350                         kg ]
```

### Validation

Errors should:

- Identify the affected field.
- Explain what needs to be corrected.
- Avoid technical backend terminology.

Example:

```text
Weight
[ -5 ]

Weight must be greater than 0.
```

---

# 30. Loading States

Use lightweight loading indicators.

For full-screen loading:

```text
CircularProgressIndicator
```

For lists:

- Skeleton/loading placeholders or compact progress indicators
- Preserve already loaded content during refresh where possible

Do not block the entire screen for small background operations.

---

# 31. Empty States

Every major list should have a meaningful empty state.

Example:

```text
No livestock found

Try changing your search or filters.

[ Clear Filters ]
```

Seller listings:

```text
No listings yet

Create your first livestock listing
to start selling on AgroBenta.

[ Create Listing ]
```

---

# 32. Error States

Errors should be understandable to normal users.

Avoid exposing raw exceptions such as:

```text
SocketException
DioError
FormatException
```

Instead use:

```text
Could not reach the server.
Please check your connection and try again.
```

For authentication:

```text
Invalid email or password.
```

For server errors:

```text
Something went wrong.
Please try again later.
```

Technical details may be logged for development but should not be the primary user-facing message.

---

# 33. Success Feedback

Use short confirmation messages.

Examples:

```text
Listing saved successfully.
```

```text
Seller verification submitted.
```

```text
Changes saved.
```

```text
Message sent.
```

Prefer SnackBars, inline confirmation, or lightweight feedback rather than unnecessary modal dialogs.

---

# 34. Icons

Use one consistent icon family throughout the application.

Recommended icon usage:

- Home
- Search
- Filter
- Favorite
- Person
- Store
- Notifications
- Message
- Transaction
- Location
- Camera
- Edit
- Delete
- Check
- Warning

Icons should support text rather than replace important labels.

Avoid mixing multiple unrelated icon styles.

---

# 35. Images

Livestock imagery is an important part of the marketplace experience.

Image rules:

- Use consistent aspect ratios in listing cards.
- Use rounded image corners.
- Maintain object-fit/cover behavior for marketplace thumbnails.
- Avoid distorted images.
- Use a meaningful placeholder when no photo is available.

The prototype emphasizes livestock images on:

- Home
- Browse
- Search results
- Livestock details
- My Listings

---

# 36. Accessibility

The mobile UI should support:

- Adequate touch targets
- Readable text
- Strong contrast
- Clear labels
- Error messages associated with fields
- Icons with semantic labels
- No information conveyed by color alone

Interactive elements should generally provide at least approximately 44–48dp of touchable area.

---

# 37. Responsive Behavior

The design must work across common Android phone sizes.

Avoid:

- Fixed-width content
- Hardcoded screen dimensions
- Text overflow
- Buttons that become inaccessible on small screens
- Horizontally scrolling forms unless necessary

Use:

- `SafeArea`
- Flexible layouts
- `Expanded`/`Flexible`
- `ListView`/`CustomScrollView`
- Responsive padding
- Scrollable forms

---

# 38. Motion

Animations should be subtle and purposeful.

Allowed:

- Page transitions
- Button feedback
- Loading transitions
- Expand/collapse
- Filter panel transitions

Avoid:

- Excessive animations
- Decorative motion
- Long transitions
- Flashy effects

---

# 39. Design Component Hierarchy

Reusable components should be preferred over duplicated screen-specific widgets.

Suggested shared components:

```text
AppBar
PrimaryButton
SecondaryButton
AppTextField
AppDropdown
StatusChip
LivestockCard
CategoryChip
SearchBar
FilterSection
PriceDisplay
SellerVerificationBadge
EmptyState
ErrorState
LoadingState
NotificationTile
TransactionCard
```

Components should remain visually consistent across all features.

---

# 40. Screen-to-Prototype Mapping

The approved prototype contains the following mobile screens:

| # | Screen |
|---:|---|
| 1 | Register Account |
| 2 | Login |
| 3 | Home |
| 4 | Become a Seller |
| 5 | Profile |
| 6 | Browse Livestock |
| 7 | Search Livestock |
| 8 | Filter Livestock |
| 9 | Livestock Details |
| 10 | Seller Information |
| 11 | Verification Status |
| 12 | Submit Seller Verification |
| 13 | Create Livestock Listing |
| 14 | Manage My Listings |
| 15 | AI Price Suggestion |
| 16 | View AI Suggestion |
| 17 | Messages |
| 18 | Transactions |
| 19 | Notifications |

These screens should use the same design system rather than introducing separate visual styles per feature.

---

# 41. Single Account UX Rule

This is a critical AgroBenta design requirement.

Do **not** create:

```text
Buyer Account
Seller Account
Switch to Seller Account
Seller Login
```

Instead:

```text
One Account
     │
     ├── Buyer capabilities
     │
     └── Become a Seller
             │
             └── Verification
                     │
                     └── Approved Seller Capability
```

The user's account remains the same before and after seller approval.

---

# 42. Seller Verification UX Rule

Seller verification controls seller capability.

The UI must reflect the server state:

```text
buyer
   ↓
Become a Seller
   ↓
Verification Submitted
   ↓
Pending Review
   ├── Approved → Seller capability
   └── Rejected → Resubmit
```

The client must not independently mark a user as verified.

---

# 43. AI UX Rule

AI price suggestion is informational.

The correct interaction is:

```text
Seller enters livestock information
            ↓
      Request estimate
            ↓
     AI price suggestion
            ↓
Seller reviews suggestion
            ↓
Seller chooses final asking price
```

The system must not present the AI estimate as a guaranteed market price.

---

# 44. Design Do / Don't

## Do

- Use AgroBenta green consistently.
- Keep screens clean.
- Use livestock imagery prominently.
- Use cards for marketplace content.
- Use clear status indicators.
- Keep primary actions obvious.
- Use bottom navigation consistently.
- Keep forms easy to scan.
- Use simple agricultural visual language.
- Preserve the single-account experience.

## Don't

- Don't use neon colors.
- Don't use glassmorphism.
- Don't use excessive gradients.
- Don't use oversized headings.
- Don't use decorative blobs.
- Don't use excessive animation.
- Don't use too many pill-shaped controls.
- Don't create separate buyer and seller accounts.
- Don't expose seller email unnecessarily.
- Don't allow the client to decide verification or listing approval status.
- Don't make AI suggestions look like guaranteed prices.

---

# 45. Implementation Priority

When implementing or refining the mobile UI, use this priority order:

1. Functional correctness
2. Navigation consistency
3. Readability
4. Form usability
5. Marketplace card consistency
6. Status visibility
7. Responsive behavior
8. Accessibility
9. Visual polish
10. Animation

Functionality must never be sacrificed for visual effects.

---

# 46. Final Visual Target

The supplied AgroBenta prototype is the visual reference for the mobile implementation.

The implementation should preserve these recognizable characteristics:

```text
Dark AgroBenta green
        ↓
White content surfaces
        ↓
Rounded cards and controls
        ↓
Livestock photography
        ↓
Compact information hierarchy
        ↓
Green primary actions
        ↓
Clear status indicators
        ↓
Simple bottom navigation
        ↓
Professional agricultural marketplace feel
```

The objective is to make the implemented Flutter application visually consistent with the approved prototype while keeping the UI practical, responsive, accessible, and aligned with the actual backend functionality.
