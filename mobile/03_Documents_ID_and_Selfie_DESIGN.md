# AgroBenta Mobile — Seller Verification: Required Documents Screen

## Purpose
Collect two distinct pieces of identity evidence: (1) a government-issued ID image and (2) a selfie showing the applicant holding that same ID. Both are required for submission unless the approved verification policy changes.

## Progress Indicator
Show Basic Information completed, Documents active, Review and Submitted upcoming.

## Required Upload 1 — Government-Issued ID
Card title: `Valid Government-Issued ID`
- Required indicator.
- Instruction: `Upload a clear photo or scan of an accepted government-issued ID. The name and details must be readable.`
- Provide `Take Photo` and/or `Choose Image` actions using existing supported picker/camera dependencies.
- Show image preview after selection.
- Provide `Change`/`Replace` and `Remove` actions before final submission.
- Validate supported file type and size based on the actual backend contract.
- Provide concise image-quality guidance: entire ID visible, readable text, no blur, glare, or cropped edges.
- Accepted ID types must follow an approved project policy. Do not invent a definitive list.

## Required Upload 2 — Selfie Holding the Same ID
Card title: `Selfie Holding Your ID`
- Required indicator.
- Instruction: `Take a clear selfie while holding the same ID beside your face. Your face and the ID should both be visible in the same photo.`
- Select/capture independently from the ID image.
- Show preview.
- Provide `Retake`/`Change` and `Remove` actions before submission.
- Do not permit the ID image to be silently reused as the selfie.
- Do not implement face matching, liveness detection, OCR, or biometric analysis unless explicitly approved and actually supported.

## Optional Documents
Proof of address and farm photos may be included only if both the approved policy and backend support them. Optional documents must never replace the required ID or selfie.

## Upload State
Represent states honestly:
- Not selected.
- Selected locally (not yet uploaded).
- Uploading.
- Uploaded successfully (only after server confirmation).
- Upload failed with retry.
- Removed/replaced.

Do not show a green uploaded state merely because an image picker returned a file.

## Navigation
- `Back` returns to Basic Information without discarding values.
- `Next` advances only when both required images satisfy the actual upload/persistence requirements.
- Prevent duplicate uploads/submissions.
- Keep selected files when navigating between steps when supported safely by the app.

## Privacy and Security
Government IDs and selfies are sensitive personal data:
- Use private, access-controlled storage.
- Do not expose public document URLs.
- Validate file content, type, and size server-side.
- Use server-generated storage names where appropriate.
- Restrict access to the submitting user and authorized reviewers.
- Do not log document content, ID numbers, access tokens, or private URLs.
- Follow existing privacy and retention policy. If policy/storage is missing, report it as a blocker.
- Do not invent endpoints, fields, storage disks, or migrations.
- Do not reset databases or Docker volumes.

## Visual Design
- Green `Seller Application` app bar.
- Four-step progress indicator.
- Heading: `Upload Required Documents`.
- Two separate, clearly labelled document cards.
- Neutral placeholder before selection; thumbnail preview after selection.
- Green outlined `Change`/`Retake` button.
- Responsive cards and scrollable layout.
- Bottom `Back` and `Next` actions.

## Acceptance Criteria
- ID and selfie are separate required images.
- Both can be previewed, replaced, and removed before submission.
- UI distinguishes local selection from successful server upload.
- Submission cannot proceed when required evidence is missing.
- Actual storage and upload contracts are verified before integration.
