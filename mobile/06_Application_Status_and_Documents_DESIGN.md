# AgroBenta Mobile — Seller Verification: Application Status and Documents Screen

## Purpose
Allow a seller to review the current verification status and see which documents were submitted, without exposing sensitive evidence to unauthorized users.

## Layout
- Green `Seller Application` app bar.
- Status card at the top showing the actual server status.
- Application Details card showing supported fields.
- Uploaded Documents section listing the required ID and selfie, plus optional files only if supported.
- `View` action only if secure, authorized document viewing is implemented.
- `Edit Application` action only when the current backend workflow permits edits.

## Status Handling
- **Pending Verification:** application is awaiting administrator review.
- **Approved:** show approval only when the backend confirms it; seller capability is still controlled by the server.
- **Rejected:** show the actual rejection information only if the backend provides it and disclosure is authorized; offer resubmission only if supported.
- Other statuses must be displayed according to the real backend contract.

Do not hardcode status or submission date. Do not invent a rejection reason.

## Document Access
- Use private, authenticated access.
- Do not expose unrestricted public URLs.
- Verify ownership on every request.
- Do not show another seller's documents.
- Avoid displaying full ID numbers unless necessary and approved.
- Do not store sensitive files in logs or analytics.

## Edit and Resubmission
- Enable editing only when permitted by the existing backend workflow.
- Preserve verification history when resubmitting if that is the current rule.
- Do not replace a prior verification record or erase history unless the existing approved contract requires it.
- If editing/resubmission is unsupported, do not show an active button that cannot work.

## Visual Design
- Clear status card with accessible color and icon.
- Basic information card.
- Document list with safe thumbnails or status indicators.
- `View` and `Edit Application` actions only when supported.
- Use existing app theme, navigation, and icon package.

## Acceptance Criteria
- Status and documents reflect actual persisted records.
- Access is limited to the authenticated owner and authorized reviewers.
- Actions match the current backend workflow.
- Unsupported edit, view, or resubmission features are not faked.
