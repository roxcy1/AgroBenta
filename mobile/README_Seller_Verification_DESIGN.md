# AgroBenta Seller Verification — Design Document Set

Use these screen-specific design documents with OpenCode. Keep them separate rather than overwriting `mobile/DESIGN.md`.

## Flutter mobile screens
1. [01 — Become a Seller Introduction](01_Become_a_Seller_Introduction_DESIGN.md)
2. [02 — Basic Information](02_Basic_Information_DESIGN.md)
3. [03 — Documents: Government ID and Selfie with ID](03_Documents_ID_and_Selfie_DESIGN.md)
4. [04 — Review Application](04_Review_Application_DESIGN.md)
5. [05 — Application Submitted](05_Application_Submitted_DESIGN.md)
6. [06 — Application Status and Documents](06_Application_Status_and_Documents_DESIGN.md)

## Admin web screen
7. [07 — Admin Seller Verification Review](07_Admin_Seller_Verification_Review_DESIGN.md)

## Important implementation constraints
- Inspect existing code and backend contracts before implementing.
- ID and selfie are separate required evidence.
- Use private, authorized storage and access; never fake upload success.
- Submission means pending review, not approval.
- Only server-side admin approval can enable seller capabilities.
- Preserve existing code, uncommitted changes, and database data.
- Do not invent endpoints, schema fields, or statuses.
