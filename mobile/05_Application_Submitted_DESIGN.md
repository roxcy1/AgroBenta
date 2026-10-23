# AgroBenta Mobile — Seller Verification: Application Submitted Screen

## Purpose
Confirm that the seller application has been successfully received by the server and explain the next steps.

## Entry Condition
Show this screen only after the backend confirms that the application and required document references/files were saved successfully. A local button tap or successful image selection is not sufficient.

## Layout
- Clean, light background.
- Green success illustration/checkmark using an existing approved asset or icon.
- Heading: `Application Submitted!`
- Supporting text: `Your seller application has been received and is now under review.` Use this wording only if the server's returned status supports it.
- Status card with clock icon and label `Pending Verification`.
- Brief explanation that an authorized team will review the application.
- A `What happens next?` section:
  1. The application will be reviewed.
  2. The applicant can check the status in the existing profile/application screen.
  3. Seller features become available only if the administrator approves the application.
- Primary action: `Back to Profile` or the existing appropriate destination.

## Status Rules
- Use the actual status returned by the backend.
- Do not invent status values or a review timeframe.
- Do not claim that a notification will arrive unless notifications are implemented.
- Submission is not approval.
- Do not enable seller-only functions while the application is pending.

## Error Handling
If the backend response is missing, malformed, or unsuccessful, do not display a success screen. Use the existing error handling and provide a retry or return path without duplicating the application.

## Visual Design
- Centered success indicator with generous spacing.
- Dark, readable heading and muted explanatory text.
- Pale amber status card for pending review, if consistent with the app's status palette.
- Pale green next-steps card.
- Full-width green button.
- Use existing icons and typography; no emoji or fabricated illustrations.
- Respect safe areas and small screens.

## Acceptance Criteria
- Only follows confirmed server-side submission.
- Status is server-derived.
- Seller privileges remain disabled until approval.
- Navigation works without resubmitting.
