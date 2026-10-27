# AgroBenta Admin Web — Seller Verification Review Design

## Purpose
Specify the admin-side review interface needed to review a seller's submitted government-issued ID and selfie holding that same ID. This screen is necessary for a genuine end-to-end verification workflow.

## Inspect First
Inspect the current React/Vite admin application, Laravel admin routes/controllers/policies/resources, seller-verification model and storage, and existing admin review UI. Reuse current architecture and authorization. Do not assume an endpoint or document storage implementation exists.

## Application Queue
Show real seller verification applications available to the authenticated administrator, with supported fields such as:
- Applicant name.
- Submission date.
- Actual verification status.
- Application identifier.
- Search/filter controls only when supported by existing APIs.

Do not display sample applicants or fake statuses in production.

## Review Detail
Display supported basic information and securely load:
- Government-issued ID.
- Selfie holding the same ID.
- Optional documents only if supported.

Requirements:
- Use an authenticated, authorized document retrieval mechanism.
- Do not use public document URLs.
- Do not put document URLs, ID numbers, or file content in logs.
- Do not let a client-supplied ID bypass server authorization.
- Show unavailable/corrupt-file errors without exposing private storage paths.

## Decision Actions
Provide Approve and Reject actions only if the current backend supports them.
- Require confirmation before making a decision.
- Reject only with a reason if the existing API/workflow requires or supports one.
- Display the result only after the server confirms the update.
- Prevent unauthorized users from reviewing or deciding applications.
- Do not let client UI alone grant seller capability.
- Preserve prior verification history on resubmission if that is the established rule.

## Security and Privacy
- Enforce admin authorization server-side.
- Restrict evidence access to authorized reviewers.
- Do not expose ID/selfie assets to ordinary users.
- Follow the approved privacy and retention policy.
- Do not implement face recognition or biometric comparison without explicit approval.
- Do not invent endpoints, migrations, storage disks, or statuses.

## Testing
Test authorized and unauthorized access, evidence loading, missing files, approve/reject flows, duplicate decisions, status persistence, and history behavior using the real contract.

## Acceptance Criteria
- Admin can review real applications and evidence securely.
- Approve/reject results persist through the backend.
- Seller capabilities update only through server-side approval logic.
- No public document exposure or fake review state.
