# AgroBenta Design System

## 1. Design Direction

AgroBenta uses a professional administrative system design.

The interface should look like a real organizational web application rather
than a generic SaaS template or AI-generated dashboard.

The visual style should be:

- clean
- practical
- professional
- readable
- consistent
- restrained
- agriculture/livestock appropriate

Avoid excessive decorative elements.

---

## 2. Visual Source of Truth

The provided AgroBenta administrator prototype is the primary visual reference.

When implementing a screen:

1. Follow the prototype structure.
2. Preserve the visual hierarchy.
3. Preserve the navigation structure.
4. Preserve the relationship between cards, tables, charts, and actions.
5. Do not redesign a screen simply to make it look more modern.

If a detail is not defined in the prototype, use the existing design system
rather than inventing a new visual style.

---

## 3. Color Direction

The primary visual direction uses dark agricultural green.

Use green primarily for:

- primary buttons
- active navigation
- important status indicators
- selected controls
- links when appropriate

The main content area should use:

- white
- light neutral backgrounds
- subtle borders
- restrained shadows

Avoid:

- neon colors
- excessive gradients
- rainbow-colored cards
- glowing effects
- glassmorphism

---

## 4. Typography

Use a conventional professional UI/system font.

Do not use a decorative or trendy display font.

Recommended hierarchy:

- Page title: 24–28px
- Section heading: 16–18px
- Body: 14px
- Secondary text: 12–13px

Do not make all text bold.

Typography should prioritize readability over visual effects.

---

## 5. Sidebar

The administrator sidebar uses a dark green background.

Navigation:

- Dashboard
- Users
- Livestock & Verification
- Transactions & Activities
- Reports
- Settings
- Logout

The current page should have a clear active state.

Do not add additional navigation items unless explicitly approved.

---

## 6. Header

Use a clean administrative header.

The header should contain only useful information and actions.

Avoid:

- unnecessary decorative icons
- oversized welcome messages
- excessive badges
- animated elements

---

## 7. Cards

Cards should be practical information containers.

Use:

- subtle borders
- restrained shadows
- moderate corner radius
- consistent internal spacing

Do not make cards excessively rounded.

Do not use large decorative illustrations.

---

## 8. Buttons

Primary actions use the AgroBenta green.

Buttons should:

- have clear labels
- use consistent height
- use consistent padding
- have readable text
- provide hover/focus states

Avoid excessive icon-only buttons.

---

## 9. Tables

Tables should prioritize information density and readability.

Use:

- clear column headings
- consistent row height
- subtle separators
- readable spacing
- clear action controls

Do not turn every table value into a pill.

---

## 10. Status Indicators

Use status badges only when they improve readability.

Examples:

- Active
- Pending
- Approved
- Rejected
- Sold
- Inactive
- Completed
- Cancelled

Status colors should be restrained and semantically meaningful.

---

## 11. Charts

Charts should communicate information clearly.

Use simple charts.

Avoid:

- 3D charts
- excessive gradients
- decorative chart effects
- unnecessary animation

Charts must use actual API/database data.

Never create fake dashboard statistics merely to make charts look populated.

---

## 12. Dashboard

The dashboard follows the administrator prototype.

Structure:

1. Page heading
2. Summary/statistic cards
3. Marketplace overview
4. Transaction/sales trend
5. Livestock distribution
6. Recent activities

The dashboard should prioritize useful administrative information.

---

## 13. Forms

Forms should use conventional administrative layouts.

Labels should be visible.

Inputs should have:

- clear borders
- readable text
- consistent height
- clear focus state
- validation messages where required

Do not hide important labels inside placeholder text.

---

## 14. Empty States

Empty states should be simple and informative.

Example:

"No transactions available yet."

Do not use fake records to avoid an empty state.

---

## 15. Loading States

Use simple loading indicators or restrained skeletons.

Avoid excessive animations.

---

## 16. Responsive Design

Desktop is the primary target for the administrator application.

The interface should remain usable on tablets and smaller screens.

Do not redesign the application into a completely different mobile-style
interface.

---

## 17. General UI Rules

DO:

- maintain consistent spacing
- reuse existing components
- maintain visual hierarchy
- keep interfaces practical
- follow the prototype
- use real system data
- maintain consistent typography

DO NOT:

- introduce random fonts
- introduce gradients everywhere
- use glassmorphism
- use excessive rounded cards
- use oversized headings
- use emoji as interface elements
- add unnecessary animations
- add decorative illustrations without approval
- create generic AI dashboard layouts
- redesign existing pages without approval

---

## 18. Implementation Principle

When choosing between:

A. a visually impressive but unnecessary design

and

B. a simple, consistent administrative interface,

choose B.

AgroBenta should look like a professionally developed information system,
not a design showcase.