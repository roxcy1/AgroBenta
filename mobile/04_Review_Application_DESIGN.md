# AgroBenta Mobile — Seller Verification: Review Application Screen

## Purpose
Allow the applicant to review all information and required evidence before submitting the seller application for administrator review.

## Progress Indicator
Show Basic Information and Documents completed, Review active, Submitted upcoming.

## Sections
### Basic Information Card
Display supported fields from the current form:
- Full Name
- Phone Number, if supported
- Address, if supported
- Farm/Business Name, if supported

Provide an `Edit` action that returns to Basic Information.

### Uploaded Documents Card
Display:
- Government-Issued ID thumbnail or secure status preview.
- Selfie Holding ID thumbnail or secure status preview.
- Optional proof of address/farm photos only if supported.
- `Edit` action to return to Documents.

Avoid showing full ID numbers or unnecessary sensitive data in text. Any thumbnail display must follow the app's privacy and access-control design.

## Submission Notice
Explain that submission sends the application for administrator review and does not guarantee approval. Do not promise a review timeframe unless officially defined.

## Submit Application
- Require all supported required fields and both required documents.
- Submit using the real API contract.
- Show progress and disable duplicate taps.
- Show success only after the server confirms that the application and documents are persisted.
- On error, show a recoverable message and preserve form state.
- Do not create a fake local `pending` result if the server failed.

## Navigation
- `Back` returns to Documents.
- Edit actions return to the correct earlier step.
- Preserve entered values and uploaded-document references when navigating.

## Data and Security
- Server derives the applicant identity from the authenticated token.
- Never trust a client-supplied user ID or verification status.
- Do not expose public document URLs.
- Do not create unsupported schema fields or routes.
- Do not grant seller capability at submission time.

## Visual Design
- Green app bar and progress indicator.
- Heading: `Review Your Information`.
- Compact white cards with subtle borders and rounded corners.
- Field labels and values with existing icons where appropriate.
- Document thumbnails and concise labels.
- Bottom outlined `Back` and filled green `Submit Application` buttons.
- Responsive, scrollable layout.

## Acceptance Criteria
- Summary matches the user's current form data.
- Edit navigation returns to the correct step.
- Both required documents are present and persisted according to the real API contract.
- Duplicate submission is prevented.
- Submission failure does not display success or discard data.
