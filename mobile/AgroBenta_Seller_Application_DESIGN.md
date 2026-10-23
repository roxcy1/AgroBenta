# AgroBenta Mobile UI Design --- Seller Application and Verification Flow

## Purpose

This specification describes the six-screen seller onboarding and
verification flow shown in the supplied reference. It is a visual and
implementation guide, not approval to invent backend fields,
verification rules, document storage, or status transitions.

Inspect the existing seller-verification feature and approved AgroBenta
functional/API documentation first. Reuse current screens and endpoints.
If the design requires fields or behaviors not supported by the current
contract, document the gap and request approval before expanding scope.

## 1. Visual System

-   Reuse AgroBenta's existing agricultural-green theme, typography,
    spacing, and components.
-   Use white/light backgrounds, pale-green information cards, and
    pale-amber pending-status cards.
-   Primary actions: dark green. Secondary actions: white with green
    border.
-   Keep forms compact, readable, and scrollable.
-   Use installed icon packages or approved local assets, not emoji or
    arbitrary Unicode glyphs.
-   Use illustrations only when approved local assets exist. Do not
    hardcode remote image URLs or fake livestock/document imagery.
-   Respect safe areas, text scaling, contrast, and touch targets.

## 2. Flow Overview

The reference depicts: 1. **Become a Seller** introduction. 2. **Basic
Information** form. 3. **Upload Required Documents**. 4. **Review Your
Information**. 5. **Application Submitted** confirmation. 6. **Pending
Verification / Application Details** with an Edit Application action.

Compare this proposed visual flow with the current implementation. Do
not duplicate existing features or add unsupported states.

## 3. Screen 1 --- Become a Seller

-   Header with back navigation and **Become a Seller** title.
-   Agricultural hero illustration/banner only if an approved local
    asset exists.
-   Heading: **Start Selling on AgroBenta**.
-   Supporting text describing seller benefits.
-   Four compact rows: **List your livestock**, **Get verified**,
    **Manage your listings**, **Connect with buyers**.
-   Primary CTA: **Get Started**.
-   Get Started opens the existing seller-verification flow.
-   Do not create a separate seller account. Seller capability is
    granted only after server-side approval.
-   Do not promise unsupported capabilities or add a duplicate entry
    screen if one already exists.

## 4. Screen 2 --- Basic Information

Reference fields: - Full Name - Phone Number - Address - Farm/Business
Name (Optional)

Layout: - Header: **Seller Application**. - Four-step progress
indicator: **Basic Information**, **Documents**, **Review**,
**Submitted**. - Heading: **Basic Information**, short explanation, form
fields, and an accuracy reminder. - Continue with **Next**.

Rules: - The screenshot's sample name, phone, address, and farm name are
illustrative; never hardcode them. - Inspect the current
`seller_verifications` schema and API request before showing/submitting
fields. - Do not add columns, request properties, or migrations for
unsupported fields without approval. - Show and submit only supported
fields; report missing ones. - Validate using existing backend rules and
preserve input on errors.

## 5. Screen 3 --- Upload Required Documents

Reference document cards: - **Valid ID** - **Proof of Address** - **Farm
Photos (Optional)**

Each card may show a preview and Upload/Change action. Progress
indicates Documents is active; Back and Next actions appear below.

Critical rules: - The screenshot does not authorize document upload by
itself. The known project had an unresolved file-storage decision and no
confirmed mobile upload flow. - Inspect approved storage and backend API
decisions before implementation. - Never fake upload success, store
private documents insecurely, create placeholder URLs, or claim a file
was uploaded when it was not. - Do not add storage services, database
columns, migrations, validation rules, or upload endpoints without
explicit approval. - If upload is not supported, stop before
implementing it and report the missing API/storage decisions. A UI-only
mock is not a completed feature.

## 6. Screen 4 --- Review Your Information

-   Header: **Seller Application**.
-   Progress indicator shows Basic Information and Documents complete,
    Review active.
-   Read-only summary of entered information and uploaded documents.
-   Edit controls only if the existing flow supports returning to a
    step.
-   Actions: Back and **Submit Application**.

Rules: - Show actual form values and confirmed uploaded files only. -
Never show fake document thumbnails or claim uploads exist without
success. - Submit through the existing approved seller-verification
endpoint. - Prevent duplicate submissions and preserve the draft on
failure. - The client must not change verification status.

## 7. Screen 5 --- Application Submitted

-   Clear success illustration/icon.
-   Heading: **Application Submitted!**
-   Confirmation that the application was received and is under review.
-   Pending-verification information card.
-   **What happens next?** explanation.
-   CTA: **Back to Profile**.

Rules: - Show only after the backend confirms submission. - Do not show
success after a failed/offline request. - Do not promise review duration
or notification channels unless established. - Status remains
server-authoritative.

## 8. Screen 6 --- Pending Verification / Application Details

-   Header: **Seller Application**.
-   Pending-verification card with current status and submission date
    only if returned by the API.
-   Application details showing available fields.
-   Uploaded-document section only if document metadata is available.
-   View action only if secure document access exists.
-   **Edit Application** only if the existing contract allows
    editing/resubmission in that state.

Rules: - Do not hardcode Pending or a submission date. - Approved users
should see the existing approved-seller state. - Rejected users follow
existing rejection/resubmission rules. - Do not add status transitions,
overwrite verification history, or expose private documents.

## 9. Business Rules to Preserve

-   A single account may browse as a buyer and request seller
    capability.
-   Seller-only features require server-side approval.
-   The client must not set `role` or `seller_capability`.
-   Preserve existing verification statuses, transitions, and history.
-   Do not change listing lifecycle, marketplace visibility, or admin
    verification behavior as part of this UI task unless separately
    approved.

## 10. Navigation

Where the app shell is visible, preserve this bottom navigation
order: 1. **Home** 2. **Browse** 3. **Messages** 4. **Transactions** 5.
**Profile**

-   The visible label must be **Browse**, not Marketplace.
-   Focused application steps may hide bottom navigation if consistent
    with existing navigation architecture.
-   Do not add nonfunctional placeholder destinations.

## 11. Architecture and API

-   Inspect `mobile/AGENTS.md`, `mobile/DESIGN.md`, seller-verification
    models/services/repositories/controllers/screens, backend
    routes/controllers/requests/models/migrations, and tests.
-   Reuse existing architecture and endpoint contracts.
-   Do not create duplicate seller-verification features.
-   Do not add fields, endpoints, migrations, storage dependencies, or
    business rules without explicit approval.
-   Do not hardcode sample personal data, document previews, status
    dates, or upload results.

## 12. Protected Areas and Git Rules

-   Preserve all existing M5/M6 work,
    Browse/filter/listing-detail/inquiry work, Docker fixes, mobile
    configuration, tests, and uncommitted modifications.
-   Do not modify `frontend/src/index.css`, root `AGENTS.md`, or root
    `DESIGN.md`.
-   Do not reset, clean, revert, or discard Git changes.
-   Do not reset the database or delete Docker volumes.
-   Do not stage, commit, or push to GitHub without explicit user
    consent.

## 13. Acceptance Criteria

1.  Screens follow the reference flow wherever supported.
2.  Submitted personal/application fields are backed by the approved
    schema/API.
3.  Document upload is implemented only with approved secure storage/API
    support.
4.  Submission success appears only after backend confirmation.
5.  Status and dates come from the backend.
6.  Seller approval remains server-controlled.
7.  Single-account and verification-history rules remain intact.
8.  `flutter analyze` and relevant seller-verification tests pass.
9.  Existing project changes are preserved; nothing is staged,
    committed, or pushed.

## 14. Final Report

Report files changed, API/schema capabilities, supported or blocked
steps, actual test results, decisions needed for unsupported
fields/document upload, and confirmation that unrelated changes were
preserved and nothing was staged, committed, or pushed.
