# AgroBenta Mobile — Design System

## 1. Scope and standing

This file is the **visual source of truth for the Flutter mobile application
only**. It governs `mobile/`.

It does not replace the root `DESIGN.md`. That file owns the AgroBenta brand
identity — the green, the restraint, the "this is a real product, not a design
showcase" principle — and it stays exactly as it is.

Root `DESIGN.md` §16 says *"Do not redesign the application into a completely
different mobile-style interface."* Read that in context: it is a rule for the
**Admin Web**, which must not collapse into a phone layout. It was not written
as a prohibition on a native app existing. This app is mobile-first by
definition, and it is a different client with a different job. The governing
principle is the closing line of the root `DESIGN.md` §18 — when choosing
between a visually impressive design and a simple, consistent one, **choose the
simple, consistent one** — applied to a phone.

The goal: **the Admin Web and this app should look like the same product
without being identical interfaces.** Same green, same restraint, same
typography discipline, same card and status language. Different layout,
different navigation, different density — because they are different devices.

Where this file and the root `DESIGN.md` differ, that difference is a
deliberate, documented mobile adaptation, listed in §18. It is not a
redefinition of the brand.

---

## 2. Design direction

```text
CLEAN · MODERN · PROFESSIONAL · AGRICULTURAL · MOBILE-FIRST
```

Priorities, in order:

1. **Usability** — one clear way to do the obvious thing
2. **Readability** — legible outdoors, one-handed, at arm's length
3. **Clear navigation** — the current location is never in doubt
4. **Touch-friendly interaction** — nothing important is small or fiddly
5. **Consistent hierarchy** — one thing is obviously the most important thing
6. **Agricultural identity** — credible and practical, not rustic-themed

A user may be standing in a field, in bright sun, on a cheap Android phone.
Design for that.

### Avoid

Excessive glassmorphism · full-screen transparency · claymorphism · neon
colours · excessive gradients · decorative blobs · excessive animation ·
oversized headings · excessive pill controls · futuristic UI · generic
AI-generated dashboard styling · emoji as interface elements.

Subtle visual depth is welcome. Turning the whole interface into glassmorphism
is not.

---

## 3. Colour

### Primary

**`#1B5E20`** — dark agricultural green. The AgroBenta identity.

Green is the main identity and accent colour. Use it for primary actions,
active navigation, selected states, key status indicators, and links where
appropriate.

Main content sits on white and light neutral backgrounds with subtle borders and
restrained shadows — never on green.

### Palette

Defined once in `lib/core/theme/app_colors.dart`. Every value is a 1:1 mirror
of a token already in `frontend/src/index.css` (`:root`), which is what keeps
the two products visibly the same brand.

| Token | Value | Use |
|---|---|---|
| `primary` | `#1B5E20` | Primary actions, app bar, active nav, brand marks |
| `primaryLight` | `#2E7D32` | Pressed states, tonal brand surfaces |
| `primaryDark` | `#0D3B12` | Text/icons on light brand surfaces |
| `background` | `#F5F5F5` | Screen background |
| `surface` | `#FFFFFF` | Cards, sheets, dialogs, fields |
| `border` | `#E0E0E0` | Hairlines, dividers, card outlines |
| `text` | `#1A1A1A` | Body and headings |
| `textSecondary` | `#666666` | Captions, helper copy, metadata |
| `success` | `#2E7D32` | Approved, active, completed |
| `warning` | `#F57F17` | Pending, awaiting review |
| `error` | `#C62828` | Rejected, failed, invalid |

This list is deliberately small. **Do not grow it casually.** Adding a colour
means answering "which existing token cannot express this?" first. If a new one
is genuinely required, add it to `AppColors` with a comment explaining why.

Never write `Color(0xFF...)` in feature code. Reach for `AppColors` or, better,
`Theme.of(context).colorScheme`.

### Status semantics

Status colour must be **semantically consistent across the whole app**. The
backend gives us these states:

```text
verification   submitted · pending_review · approved · rejected
listing        draft · pending · active · sold · inactive
transaction    pending · completed · cancelled
```

Suggested mapping — confirm it once, in `widgets/`, and reuse:

| State | Colour |
|---|---|
| `approved`, `active`, `completed` | `success` |
| `submitted`, `pending_review`, `pending`, `draft` | `warning` |
| `rejected`, `cancelled` | `error` |
| `sold`, `inactive` | `textSecondary` |

Status is communicated by **text plus colour**, never colour alone. A
colour-blind user must be able to read "Pending review" without distinguishing
amber from green. This is also a hard requirement for the Admin Web's
parity — the same word must mean the same thing in both apps.

---

## 4. Typography

The platform UI font — Roboto on Android, SF on iOS. This is the mobile
equivalent of the root `DESIGN.md` §4 requirement for "a conventional
professional UI/system font".

**Do not bundle or download a display font.** No Google Fonts, no custom
`.ttf`. `pubspec.yaml` declares no `fonts:` block and must keep it that way
unless there is a specific, approved reason.

### Scale

Defined in `AppTheme._textTheme`.

| Role | Size | Weight | Notes |
|---|---|---|---|
| Page title | 24 / 28 | w600 | `headlineSmall` / `headlineMedium` |
| Section heading | 18 / 16 | w600 | `titleLarge` / `titleMedium` |
| Card & list title | 14 | w600 | `titleSmall` |
| Body | 16 / 15 | w400 | `bodyLarge` / `bodyMedium` |
| Secondary | 13 | w400 | `bodySmall` |
| Label / chip | 12 | w500 | `labelMedium` |

### Documented deviation from the web

The web scale (§4 of the root file) bottoms out at a 14px body and 12–13px
secondary. **On mobile, body text is 15px and secondary is 13px.**

A 14px body on a desktop monitor held at arm's length is fine. The same 14px on
a 5-inch phone, outdoors, is at the low end of comfortable — and Flutter
logical pixels are not CSS pixels at typical device pixel ratios, so the
apparent size is smaller still.

Page-title and section-heading sizes are kept **identical** to the web. The
adjustment is limited to body copy, where legibility actually matters. This is
the one deliberate typographic divergence, and it is small.

### Rules

* Do not make everything bold. Reserve `w600` for titles and headings.
* Never use text alone to convey a price, status or action. Pair with layout,
  colour, or an icon.
* Truncate with an ellipsis rather than shrinking text to fit.
* Prices are prominent, left-aligned, and never inside a pill.
* Respect the OS text-size setting. Do not hard-code text scaling, and do not
  clamp it — a fixed-height row that clips at 200% font scale is a bug.

---

## 5. Spacing

Defined in `AppSpacing`. Every gap in the app is one of these values.

| Token | Value | Typical use |
|---|---|---|
| `xxs` | 4 | icon-to-label, badge padding |
| `xs` | 8 | label-to-field |
| `sm` | 12 | between related elements, list item padding |
| `md` | 16 | **workhorse** — card padding, screen gutter |
| `lg` | 20 | between grouped blocks |
| `xl` | 24 | between sections |
| `xxl` | 32 | between major page regions |

* Screen gutter is **16** on both edges (`AppSpacing.screenGutter`).
* Never invent an off-scale value like 14 or 18 to make something fit. Change
  the token or change the layout.

---

## 6. Shape and elevation

Defined in `AppRadius` and `AppSizes`.

| Token | Value | Use |
|---|---|---|
| `AppRadius.sm` | 6 | inputs, small buttons, chips |
| `AppRadius.md` | 8 | list tiles, secondary surfaces |
| `AppRadius.lg` | 12 | **cards — the default** |
| `AppSizes.controlHeight` | 48 | inputs and buttons |
| `AppSizes.minTouchTarget` | 48 | **minimum for anything tappable** |
| `AppSizes.appBarHeight` | 56 | app bar |

### Depth

**Borders first, shadows second.**

* Cards: `elevation: 0`, a 1px `AppColors.border` outline, `AppRadius.lg`.
* The web uses a very subtle card shadow
  (`0 1px 2px rgba(16,24,40,.04), 0 1px 3px rgba(16,24,40,.06)`). On mobile,
  where cards sit on a scrolling surface, a border alone usually separates
  content more reliably and survives dark-mode adaptation. If a shadow is
  needed, keep it at that same subtlety — never a large drop shadow.
* Modals and bottom sheets may carry a stronger shadow, because they genuinely
  float above the content.

### Touch targets

Every interactive element is **at least 48×48**, even when the visible icon or
label is smaller. Use `InkWell`/`GestureDetector` with a padded `SizedBox`, or
Material's own components, rather than shrinking the target to fit the glyph.

---

## 7. Components

### Cards

The primary information container. Practical, not decorative.

* White `AppColors.surface`, 1px border, 12px radius.
* Internal padding `AppSpacing.md` (16).
* One card = one idea. Do not nest cards inside cards.
* No large decorative illustrations.
* A card may be tappable as a whole, but must still expose its primary action
  as a distinct, correctly sized target.

### Buttons

* **Primary** — filled `AppColors.primary`, white label. One per screen. The
  single most important action.
* **Secondary** — outlined, `AppColors.primary` label. Genuine alternatives.
* **Tertiary** — text button. Low-stakes, inline, dismissible.
* Consistent `AppSizes.controlHeight` (48) and `AppRadius.sm`.
* Labels are verbs: "Sign in", "Submit for review", "Mark as sold".
* Destructive actions (delete listing, cancel transaction) use `error` and must
  confirm.
* Avoid icon-only buttons. When an action is icon-only, it still needs a
  tooltip and a 48px target.
* Every async action needs a loading state and must not double-fire on tap.

### Status indicators

Use a restrained chip: subtle background tint, matching text colour, 6px radius,
`labelMedium` text. The status **word** carries the meaning.

Do not turn every value into a pill. Prices, names and dates are plain text.

### Forms

* Visible labels, always floating (`FloatingLabelBehavior.always`). Never hide a
  label inside placeholder text — it vanishes the moment the user types.
* 1px `AppColors.border`; 2px `AppColors.primary` on focus; `error` on invalid.
* 48px minimum height.
* Validation errors appear **below** the field, in `error` colour, in
  `bodySmall`. Map them from `ApiException.validationErrors` (Laravel 422).
* Group related fields; use `AppSpacing.xl` between groups.
* Do not validate only on submit for things checkable immediately.

### Lists

* `ListTile` for rows. Generous vertical padding — a livestock listing row is
  tappable with a thumb, not a fingertip.
* One row per record, leading image or icon, title, secondary metadata, trailing
  status or chevron.
* **Infinite scroll or explicit pagination, never both.** The backend paginates
  with `{current_page, last_page, per_page, total}` — use `Pagination`.
* Never render a full-bleed table. There are no tables on a phone.

### Images

Livestock photos are the strongest signal of value in a marketplace, and the
brief calls for strong image presentation.

* Give photos real estate. A listing card leads with the image, roughly 4:3,
  with a consistent aspect ratio so grids align.
* Use a `BoxFit.cover` crop; never distort an animal to fill a frame.
* Always provide a placeholder and a failed-load state. A grey box with a
  broken image reads as a bug.
* Respect loading state: shimmer or a neutral placeholder, nothing elaborate.
* Do not use the first photo as the app icon or a background.

**Note:** no image currently reaches the client. `listings.photos` exists as a
JSON column but `ListingResource` does not expose it (GAP-06). Image
presentation is designed for here so it is ready, but it cannot be built until
the backend decides how photos are uploaded and served.

### Feedback

* **Loading** — a restrained `CircularProgressIndicator` in `AppColors.primary`,
  or simple skeletons. No shimmer gradients, no pulsing, no spinner theatre.
* **Empty** — plain, informative copy. "No listings available yet." Never
  fabricate records to avoid an empty state (root `DESIGN.md` §14).
* **Error** — say what happened and offer a retry. Prefer the server's
  `message` when it is meaningful.
* **Success** — a snackbar for lightweight confirmation. Use it for "Listing
  submitted", not as the only record of a significant action.

---

## 8. Navigation

Desktop uses a permanent sidebar. A phone does not have room for one, and a
sidebar that collapses into a hamburger hides the app's structure from the
people who use it most.

**Use bottom navigation for the top-level destinations** — 3 to 5 items, always
visible, with a clear active state in `AppColors.primary`. This is the single
biggest structural difference from the Admin Web, and it is the right one.

Suggested top level, subject to what the backend actually exposes:

```text
Home · Marketplace · Transactions · Notifications · Profile
```

* Seller-only destinations (listing management, verification status) appear in
  context — on the profile screen, or inside the marketplace for an approved
  seller — not as permanent tabs that a buyer cannot use.
* Secondary flows (listing detail, verification submission, message thread) are
  pushed routes.
* The back behaviour is the platform default. Do not trap users.
* Every screen has an unambiguous title.

**Never build navigation for screens that do not exist.** The M0 app has one
placeholder screen and no navigation at all, on purpose.

---

## 9. Screens and states

Every screen must handle all of these. A screen that handles only the happy
path is unfinished.

| State | Requirement |
|---|---|
| Loading | Restrained indicator; no layout jump |
| Empty | Informative copy; no fake data |
| Error | What happened + retry |
| Offline / unreachable | Distinct from a server error — `ApiErrorKind.network` |
| Unauthenticated | Route to sign-in (`ApiException.requiresReauthentication`) |
| Forbidden | "You don't have permission", not a crash (GAP-11 seller scoping) |
| Success | Confirmed, then return to a sensible place |

Keep content reachable when the keyboard is up. Use
`SingleChildScrollView` and `SafeArea`.

---

## 10. Accessibility

Non-negotiable, not a follow-up task.

* **Contrast** — body text and icons meet WCAG AA (4.5:1) against their actual
  background. Do not assume; `AppColors.text` on `AppColors.background` passes,
  `AppColors.textSecondary` is close to the floor — check it on tinted chips.
* **Never colour alone** — pair every status with text or an icon.
* **Touch targets** — 48dp minimum, per §6.
* **Screen readers** — every image has a semantic label; icon-only controls have
  labels; nothing meaningful is conveyed only visually.
* **Text scaling** — the layout must survive 200% font size without clipping or
  overlapping.
* **Motion** — no information is conveyed by animation alone, and there is
  nothing to reduce.

---

## 11. Anti-patterns

Do not ship:

* Glassmorphism or blurred translucent surfaces over photography.
* Neon, glow, or a saturated gradient background.
* More than one accent colour competing with the green.
* A different border radius on every component.
* A pill for every value, including prices and dates.
* A heading that fills the screen to announce a short title.
* Animation on list scroll, page transitions, or status changes for their own sake.
* Emoji as interface icons.
* A skeleton that does not match the shape of the real content.
* Placeholder lorem-ipsum content, or invented listings to fill a screen.
* Icon-only buttons with no label and a target under 48dp.
* Two ways to reach the same screen.

---

## 12. Implementation

* All of the above is already expressed in `lib/core/theme/`. A screen should
  need **no local colour, radius, or text-style declarations**. If it does,
  the token is missing — add it there rather than styling locally.
* Reuse widgets from `lib/widgets/` once a second feature needs one.
* Business logic does not live in `build`. See `mobile/AGENTS.md` §A.
* `Material` conventions apply — the app is Material 3, and deviating from
  component behaviour (ripples, focus order, semantics) costs accessibility.

---

## 13. Open items

Report, do not decide unilaterally:

* ~~No approved functional documentation exists~~ — **closed.** It now lives at
  `docs/AGROBENTA_FUNCTIONAL_DOCUMENTATION.md`. Visual rules are documented here;
  business rules are documented there. This file governs appearance only and must
  never restate a business rule.
* **No imagery reaches the client** (GAP-06), so the image direction in §7 is
  specified but not yet buildable.
* **`livestock_type` is free text** in the schema. The marketplace needs a
  controlled vocabulary before filter chips can be designed. This is a business
  rule, not a visual one.
* **No dark mode.** Light-only is a deliberate M0 decision. Adding a dark theme
  is real work, not a palette inversion, and should be its own phase.

---

## 14. Summary

AgroBenta mobile should look like a well-made agricultural app: green, calm,
legible, and obvious. A farmer should be able to find a listing, judge the
animal from its photo, and message the seller without being taught how.

It should look like the Admin Web the way a good mobile app looks like its
desktop counterpart — same product, same restraint, same colour, sized for the
device in the hand.
