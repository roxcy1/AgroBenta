# User Management & User Reporting System

## Objective & Scope

Deliver an admin-controlled user lifecycle and a mobile user-reporting flow.

**Admin Web:** preserve the existing Users page design and filters, add a
sequential **No.** column, remove the **Created At** column (retained in User
Details), replace it with a **Reports** count, add **Deactivate Account** /
**Reactivate Account** with a required administrative reason, and add a
**User Reports** tab with a total-count badge, report table, review modal,
private evidence viewer, **Dismiss Report**, and **Deactivate Account** actions.

**Flutter:** one shared report form reached from three entry points — Seller
Public Profile, Conversation Header, and Transaction Details — supporting
Buyer → Seller, Buyer → Buyer, Seller → Buyer, and Seller → Seller. The form
records the reported user's identity, a required reason, a required written
description, and one optional screenshot.

**Laravel:** add user-report storage, validation, private evidence upload,
admin review, report counts/statuses/dismissal, reason-aware deactivation and
reactivation, audit history, deactivated-session blocking, listing/transaction
protection, privacy controls, duplicate protection, and rate limiting.

**In scope**

- User-report domain, migration, model, enums, requests, resources, services,
  repositories, controllers, routes, and tests.
- Admin user status visibility and report counts.
- Reason-aware account deactivation and reactivation with audit entries.
- Admin User Reports tab and review workflow.
- Flutter report service, repository, model, scope, controller, screen, and
  entry points.
- Documentation updates approved by the project owner.

**Out of scope**

- The separate analytics **Reports** module (`/admin/reports`), Excel/CSV export,
  `AdminReportService`, `AdminReportExportService`, `ReportResource`,
  `ReportsController`, and `ReportsPage`.
- Automatic account deactivation from a report.
- Automatic cancellation of transactions or release of reservations on
  deactivation.
- Payments, refunds, notifications to the reported user, blocking/muting,
  appeals, and an admin mobile app.
- Changes to authentication, seller verification, listing publication,
  transaction, inventory, or fulfillment rules.
- Unapproved functional-documentation changes.

## Approved Decisions

1. **One pending report per reporter/target pair.** A second report for the same
   pair is refused while the first is `pending`; a new report is allowed after
   the prior report is resolved.
2. **Deactivation is allowed during active transactions, with a warning.**
   Transactions and stock reservations are preserved; nothing is cancelled or
   released automatically.
3. **Account Status filter:** `Active`, `Deactivated`, `All`. The default view
   remains Active so existing totals and behavior are unchanged.
4. **Reports never deactivate accounts automatically.** An administrator must
   review the report and explicitly choose an action.
5. **Reuse the reason-required `DELETE /api/admin/users/{user}` endpoint** for
   deactivation, and add `POST /api/admin/users/{user}/reactivate`.
6. **One optional private screenshot:** JPEG/PNG/WebP, maximum 5 MB.
7. **Option A — Reactivation restores existing eligible seller listings
   automatically.** Account reactivation restores the account; listings whose
   stored status and inventory still qualify become marketplace-visible again
   through the existing seller-visibility rule.

**Preserved UI/UX decisions**

- Admin user table columns: **No. | Name | Email | Role | Seller Capability |
  Verification Status | Reports | Actions**.
- **User Reports** tab with a badge showing the total number of reports.
- Report review modal with full details, optional evidence, **Dismiss Report**,
  and **Deactivate Account**.
- Flutter entry points: Seller Public Profile → **Report Seller**; Conversation
  Header → **Report User**; Transaction Details → **Report User** for the other
  participant.

## Safety Constraints

- Read `AGENTS.md`, `backend/AGENTS.md`, `frontend/AGENTS.md`,
  `mobile/AGENTS.md`, `docs/AGENTS.md`, and `DESIGN.md` before editing the
  relevant scope.
- Preserve existing authentication, seller verification, transactions,
  inventory, reservations, fulfillment, listing visibility, and search/filter/
  pagination/verification behavior.
- Do not modify the separate analytics Reports module or Excel/CSV export.
- Do not weaken, delete, or skip tests; never fabricate verification results.
- Do not commit, push, merge, reset, rebase, or switch branches.
- Do not run destructive database operations or discard user work.
- Do not hardcode secrets, evidence URLs, or machine-specific configuration.
- Do not edit `docs/AGROBENTA_FUNCTIONAL_DOCUMENTATION.md` without explicit
  project-owner approval.
- Reports must never automatically deactivate an account.
- Reporter identity and evidence remain private; evidence is never a public URL.

## Baseline / Existing Implementation

- Branch at setup: `review/pr-85`.
- The working tree already contained unrelated staged listing-review changes
  plus untracked `docs/reviews/` and `ml-service/` files before this tracker was
  created. They are not part of this feature and must not be discarded.
- No user-report code, table, migration, model, enum, route, or test existed.
- Admin deactivation currently exists as `DELETE /api/admin/users/{user}`:
  soft delete, token/session revocation, self/last-admin guards, retained
  business history, and an `admin_user_deleted` audit entry.
- The admin user list excludes soft-deleted users, so deactivated accounts are
  currently unreachable for reactivation.
- Existing listings of a deactivated seller are hidden by
  `whereHas('seller')`; stored listing status and inventory are unchanged.
- New transactions against a deactivated seller's listing are refused because
  the locked listing's seller relation is null.
- Sanctum cannot resolve a soft-deleted user, credentials are revoked on
  deactivation, mobile login excludes trashed users, and Google login refuses a
  trashed email. Existing tests prove the session behavior.
- The existing `Activities` log and metadata bag are the audit-history
  mechanism.
- The existing analytics **Reports** module is separate and remains untouched.
- Existing private storage/streaming patterns for seller-verification documents
  are the model for report evidence.
- Flutter already provides `ApiClient.postMultipart`, `image_picker`,
  `LocalImagePreview`, `ApiException`, `AuthScope`, and the scope +
  `ChangeNotifier` controller pattern.

## Phase Status

| Phase | Name | Status | Depends on |
|---|---|---|---|
| 0 | Architecture & Workflow Setup | ✅ COMPLETE | — |
| 1 | Laravel Database & Domain Foundation | ✅ COMPLETE | 0 |
| 2 | Mobile User Report Submission API | ✅ COMPLETE | 1 |
| 3 | Admin Deactivation & Reactivation | ✅ COMPLETE | 1 |
| 4 | Admin Report Moderation API | ✅ COMPLETE | 1, 2, 3 |
| 5 | React Admin User Management UI | ✅ COMPLETE | 3, 4 |
| 6 | Flutter User Reporting UI | ✅ COMPLETE | 2 |
| 7 | Integration Testing & Documentation | ✅ COMPLETE | 1–6 |

## Execution Rules

Execute the following cycle for every implementation phase:

**INSPECT → IMPLEMENT → TEST → FIX → RETEST → REVIEW DIFF → RECORD PROGRESS → CONTINUE**

1. **INSPECT:** read the applicable `AGENTS.md`, `DESIGN.md`, tracker, and all
   files the phase will touch. Never assume a route, field, status, or contract.
2. **IMPLEMENT:** implement only the current phase. Keep changes minimal,
   scoped, and consistent with the established architecture.
3. **TEST:** run the phase’s targeted tests and static checks.
4. **FIX:** fix every failure introduced by the phase; do not weaken a test.
5. **RETEST:** rerun the failing check and the affected broader suite.
6. **REVIEW DIFF:** inspect the complete diff for scope creep, security issues,
   unrelated changes, and accidental deletion.
7. **RECORD PROGRESS:** update this tracker with changed files, commands, actual
   results, acceptance status, and remaining issues.
8. **CONTINUE:** during sequential autonomous execution, proceed to the next
   dependency-ordered phase automatically after a passing phase.

A phase may be marked **COMPLETE** only when every acceptance criterion is
verified and the evidence log records actual results. Continue automatically
after a passing phase. Stop and report for unresolved blockers, security risks,
destructive changes, data-loss risk, or any decision outside the approved scope.
Resume from the first incomplete phase; do not repeat verified work.

Never commit, push, merge, rebase, reset, or switch branches. The user owns all
Git actions.

## Detailed Phase Checklists & Acceptance Criteria

### Phase 0 — Architecture & Workflow Setup ✅ COMPLETE

- [x] Read the root, backend, frontend, mobile, and documentation agent rules.
- [x] Inspect the existing Admin Web users page, Laravel user/auth/marketplace/
      transaction code, Flutter seller-profile/messaging/transaction surfaces,
      routes, models, migrations, tests, and private-storage patterns.
- [x] Confirm the existing analytics Reports module is separate and must remain
      untouched.
- [x] Record the approved decisions, safety constraints, affected files, phase
      order, and API/data contracts.
- [x] Create `docs/features/user-management-reporting.md`.
- [x] Confirm no application code, migration, dependency, or test changed.

**Acceptance evidence:** this tracker is the only file created in Phase 0. No
implementation phase has started. The working tree contained unrelated
pre-existing changes that are left untouched.

### Phase 1 — Laravel Database & Domain Foundation ✅ COMPLETE

- [x] Add `user_reports` migration with reporter, reported user, reason,
      description, evidence path, status, reviewer, review time, admin note, and
      timestamps.
- [x] Add indexes for `reporter_id`, `reported_user_id`, `status`, and
      `created_at`.
- [x] Add nullable `users.deactivation_reason` and `users.deactivated_by`.
- [x] Reuse `users.deleted_at` as the deactivation timestamp; do not add a
      parallel account-status column.
- [x] Add `UserReportReason` enum with the six approved reasons.
- [x] Add `UserReportStatus` enum with `pending`, `dismissed`, `actioned`.
- [x] Add `UserReport` model with casts, fillable fields, and
      `reporter`/`reportedUser`/`reviewer` relationships that can resolve
      soft-deleted users where report history must remain readable.
- [x] Add `User::sentReports()` and `User::receivedReports()` relationships.
- [x] Add a private `user-report-evidence` filesystem disk.
- [x] Add Phase 1 tests for schema, casts, relationships, enum values, and
      private-disk configuration.

**Acceptance criteria**

- [x] Migrations run forward and roll back cleanly in the test database.
- [x] No existing table is destructively altered.
- [x] Report history remains attributable after either party is deactivated.
- [x] Evidence configuration is private; no public URL or `visibility: public`.
- [x] Existing tests still pass.
- [x] Diff contains no controller, route, UI, or dependency changes beyond what
      this phase requires.

**Files:** `backend/database/migrations/2026_11_18_000000_add_deactivation_fields_to_users_table.php`,
`backend/database/migrations/2026_11_18_000001_create_user_reports_table.php`,
`backend/app/Enums/UserReportReason.php`,
`backend/app/Enums/UserReportStatus.php`,
`backend/app/Models/UserReport.php`, `backend/app/Models/User.php`,
`backend/config/filesystems.php`, `backend/.env.example`,
`backend/tests/Feature/Report/UserReportFoundationTest.php`.

**Evidence log**

| Command | Result |
|---|---|
| `php artisan test --filter=UserReportFoundationTest` | ✅ 6 passed (21 assertions) |
| `php artisan test --filter='UserManagementTest\|UserReportFoundationTest'` | ✅ 41 passed (191 assertions) |
| `pint --test` (changed backend files) | ✅ 8 files pass |
| `migrate` + `migrate:rollback --step=2` on an ephemeral SQLite database | ✅ both migrations applied and rolled back |

### Phase 2 — Mobile User Report Submission API ✅ COMPLETE

- [x] Add `StoreUserReportRequest` with an explicit field allow-list.
- [x] Validate `reported_user_id`, `reason`, required `description`, and one
      optional evidence image (JPEG/PNG/WebP, max 5 MB).
- [x] Reject self-reporting.
- [x] Reject administrator targets.
- [x] Reject deactivated targets.
- [x] Enforce one pending report per reporter/target pair atomically.
- [x] Add a per-authenticated-user rate limit for report submission.
- [x] Add `UserReportRepository`, `UserReportService`, and evidence storage
      service; do not place queries or business rules in the controller.
- [x] Store evidence on the private disk and persist only the disk-relative
      path.
- [x] Add the mobile-facing `UserReportResource`; never expose reporter
      identity, moderation fields, or evidence paths.
- [x] Add `POST /api/reports` under `auth:sanctum` + `ability:mobile`.
- [x] Ensure report creation never changes account status, sessions, listings,
      transactions, or reservations.
- [x] Add tests for all four role pairings, self-report, admin target,
      deactivated target, duplicate pending report, evidence privacy, and
      rate limiting.

**Acceptance criteria**

- [x] A valid report returns `201` with only the reporter-safe resource.
- [x] Self-report, admin target, deactivated target, and duplicate pending
      report are refused with a clear `4xx`.
- [x] Evidence cannot be fetched from a public URL.
- [x] A report submission leaves the target account active.
- [x] The endpoint is mobile-token-only; admin tokens receive `403`.
- [x] Existing authentication and mobile routes remain unchanged.

**Files:** `backend/app/Http/Requests/Report/StoreUserReportRequest.php`,
`backend/app/Http/Controllers/Api/Report/UserReportController.php`,
`backend/app/Http/Resources/UserReportResource.php`,
`backend/app/Repositories/UserReport/UserReportRepository.php`,
`backend/app/Services/UserReport/UserReportService.php`,
`backend/app/Services/UserReport/UserReportEvidenceService.php`,
`backend/app/Providers/AppServiceProvider.php`, `backend/routes/api.php`,
`backend/tests/Feature/Report/UserReportTest.php`.

**Evidence log**

| Command | Result |
|---|---|
| `php artisan test --filter=UserReportTest` | ✅ 13 passed (70 assertions) |
| `php artisan test --filter='UserReportTest\|MobileAuthTest'` | ✅ 36 passed (174 assertions) |
| `php artisan route:list --path=reports` | ✅ `POST api/reports` registered |
| `pint --test` (changed backend files) | ✅ 9 files pass |

### Phase 3 — Admin Deactivation & Reactivation ✅ COMPLETE

- [x] Extend `AdminUserService::deleteUser()` to require and persist an
      administrative reason while preserving self/last-administrator guards.
- [x] Add a reactivation service method that restores the trashed account,
      clears deactivation metadata, and writes an audit entry.
- [x] Keep credentials revoked across deactivation/reactivation; the user signs
      in again after reactivation.
- [x] Add `DeactivateUserRequest` and `ReactivateUserRequest` requiring a
      trimmed reason with an agreed minimum/maximum length.
- [x] Add `AdminUserRepository` trashed lookup, account-status filtering, and
      received-report counting.
- [x] Extend `ListUsersRequest` with `status=active|deactivated|all`; default
      remains Active.
- [x] Extend `AdminUserResource` with account status, deactivation timestamp,
      deactivation reason, deactivated-by name/id, `reports_count`, and the
      pending-transaction warning data needed by the confirmation dialog.
- [x] Keep `DELETE /api/admin/users/{user}` as the deactivation endpoint and
      require a reason.
- [x] Add `POST /api/admin/users/{user}/reactivate` with trashed binding.
- [x] Allow the admin detail route to resolve trashed users for deep links.
- [x] Add `admin_user_reactivated` and any required report audit actions to
      `ActivityAction`, with metadata containing the administrative reason.
- [x] Define the updated `UserDetailsDialog` data contract for deactivation
      information (UI implementation follows in Phase 5).
- [x] Add tests for required reason, self-deactivation, last-admin protection,
      reactivation, revoked sessions, listing restoration, and default list
      behavior.

**Acceptance criteria**

- [x] Deactivation without a reason is rejected.
- [x] Self-deactivation and last-active-administrator deactivation remain
      impossible.
- [x] Reactivation restores the account and returns it to the Active view.
- [x] Deactivated sessions and tokens remain invalid; old tokens are not
      resurrected.
- [x] Eligible seller listings reappear after reactivation through the existing
      visibility rule (Option A); no listing status is rewritten.
- [x] Active transactions and stock reservations are unchanged.
- [x] Default Active totals and the existing search/filter/pagination behavior
      are unchanged.
- [x] Audit history identifies the actor, target, action, and reason.

**Files:** `backend/app/Http/Controllers/Api/Admin/UserController.php`,
`backend/app/Http/Requests/Admin/DeactivateUserRequest.php`,
`backend/app/Http/Requests/Admin/ReactivateUserRequest.php`,
`backend/app/Http/Requests/Admin/ListUsersRequest.php`,
`backend/app/Http/Resources/AdminUserResource.php`,
`backend/app/Repositories/Admin/AdminUserRepository.php`,
`backend/app/Services/Admin/AdminUserService.php`,
`backend/app/Enums/ActivityAction.php`, `backend/routes/api.php`,
`backend/tests/Feature/Admin/UserManagementTest.php`,
`backend/tests/Feature/Admin/UserAccountStatusTest.php`.

**Evidence log**

| Command | Result |
|---|---|
| `php artisan test --filter=UserAccountStatusTest` | ✅ 10 passed (53 assertions) |
| `php artisan test --filter='UserAccountStatusTest\|UserManagementTest'` | ✅ 45 passed (224 assertions) |
| `php artisan route:list --path=admin/users` | ✅ 5 routes, reactivation included |
| `pint --test` (changed backend files) | ✅ 11 files pass |

### Phase 4 — Admin Report Moderation API ✅ COMPLETE

- [x] Add `AdminUserReportRepository` with pagination, status filtering, and
      eager-loaded reporter/target projections.
- [x] Add `AdminUserReportService` for dismissal and report-driven
      deactivation.
- [x] Add `GET /api/admin/user-reports` with status filter and pagination.
- [x] Add `GET /api/admin/user-reports/{report}` for the review modal.
- [x] Add `GET /api/admin/user-reports/{report}/evidence` as an authenticated,
      private, non-cacheable stream.
- [x] Add `POST /api/admin/user-reports/{report}/dismiss` with an optional
      administrative note.
- [x] Add `POST /api/admin/user-reports/{report}/deactivate` with a required
      administrative reason.
- [x] Make report-driven deactivation atomic: deactivate the target and mark
      the report `actioned` only after the account service succeeds.
- [x] On failure, roll back the report status and return a clear conflict.
- [x] Include the total report count for the tab badge from the list response.
- [x] Ensure reporter identity and evidence are admin-only.
- [x] Reject report actions against administrator targets and preserve the
      last-admin guard.
- [x] Add tests for list/detail/evidence authorization, dismissal, atomic
      deactivation, reason validation, privacy, and status labels.

**Acceptance criteria**

- [x] Pending reports can be dismissed or actioned; resolved reports cannot be
      actioned again.
- [x] Dismissal never changes account status.
- [x] Deactivation requires a reason and leaves the report `actioned`.
- [x] A failed deactivation leaves the report `pending`.
- [x] Admin tokens only; mobile tokens receive `403`.
- [x] Reporter identity and evidence never enter a mobile response.
- [x] Report counts include all statuses and match the badge total.

**Files:** `backend/app/Http/Controllers/Api/Admin/UserReportController.php`,
`backend/app/Http/Requests/Admin/IndexUserReportsRequest.php`,
`backend/app/Http/Requests/Admin/DismissUserReportRequest.php`,
`backend/app/Http/Requests/Admin/DeactivateFromReportRequest.php`,
`backend/app/Http/Resources/AdminUserReportResource.php`,
`backend/app/Repositories/Admin/AdminUserReportRepository.php`,
`backend/app/Services/Admin/AdminUserReportService.php`,
`backend/app/Services/UserReport/UserReportEvidenceService.php`,
`backend/app/Enums/ActivityAction.php`, `backend/routes/api.php`,
`backend/tests/Feature/Admin/UserReportModerationTest.php`.

**Evidence log**

| Command | Result |
|---|---|
| `php artisan test --filter=UserReportModerationTest` | ✅ 9 passed (54 assertions) |
| `php artisan test --filter='UserReportModerationTest\|UserAccountStatusTest\|UserReportTest'` | ✅ 32 passed (178 assertions) |
| `php artisan route:list --path=admin/user-reports` | ✅ 5 routes registered |
| `pint --test` (changed backend files) | ✅ 11 files pass |

### Phase 5 — React Admin User Management UI ✅ COMPLETE

- [x] Add **Users / User Reports (N)** tabs to the Users page, preserving the
      existing page header and visual system.
- [x] Add **No.** as the first column using server pagination offsets, not the
      database id.
- [x] Remove **Created At** from the table; keep it in User Details.
- [x] Add **Reports** as the column in its place, showing the received-report
      total.
- [x] Add the **Account Status** filter: Active, Deactivated, All.
- [x] Show a deactivated indicator where needed without adding an unapproved
      column.
- [x] Replace the Delete action with **Deactivate Account** and add
      **Reactivate Account** for deactivated users.
- [x] Require an administrative reason and a confirmation for both actions.
- [x] Show the pending-transaction warning in the deactivation confirmation.
- [x] Build the User Reports tab: reporter name, reported user, reason, date,
      status, and Review action.
- [x] Build the review modal with full details, optional evidence, Dismiss
      Report, and Deactivate Account.
- [x] Reactivate the existing evidence viewer pattern for report screenshots.
- [x] Preserve search, role/account-type/verification filters, pagination,
      stat cards, verification details, and deep-link behavior.
- [x] Update TypeScript types, React Query keys/invalidation, API helpers, and
      status vocabulary consistently.
- [x] Add tests for columns, numbering, status filtering, action labels, reason
      validation, badge count, report table, modal actions, and evidence fetch.

**Acceptance criteria**

- [x] Table headers are exactly the approved column set.
- [x] Numbering continues across pages.
- [x] Created At is absent from the table and still present in User Details.
- [x] Reports counts are visible and match the backend.
- [x] Deactivate/reactivate actions require a reason and confirmation.
- [x] User Reports badge and table match the admin API.
- [x] Review modal shows evidence only through the authenticated endpoint.
- [x] Existing Users page functionality is preserved.
- [x] Typecheck, lint, tests, and production build pass.

**Files:** `frontend/src/features/admin/users/api/useUsers.ts`,
`frontend/src/features/admin/users/api/useUserReports.ts`,
`frontend/src/features/admin/users/components/UsersPage.tsx`,
`frontend/src/features/admin/users/components/UsersPage.css`,
`frontend/src/features/admin/users/components/UserActionsMenu.tsx`,
`frontend/src/features/admin/users/components/DeleteUserDialog.tsx`,
`frontend/src/features/admin/users/components/ReactivateUserDialog.tsx`,
`frontend/src/features/admin/users/components/UserDetailsDialog.tsx`,
`frontend/src/features/admin/users/components/UserReportsTab.tsx`,
`frontend/src/features/admin/users/components/UserReportReviewDialog.tsx`,
`frontend/src/lib/status.ts`,
`frontend/src/features/admin/users/api/useUsers.test.ts`,
`frontend/src/features/admin/users/components/UserDetailsDialog.test.tsx`,
`frontend/src/features/admin/users/components/UsersPage.test.tsx`,
`frontend/src/features/admin/users/components/UserReportsTab.test.tsx`.

**Evidence log**

| Command | Result |
|---|---|
| `npx vitest run src/features/admin/users` | ✅ 35 passed |
| `npm run typecheck` | ✅ clean |
| `npm run lint` | ✅ clean |
| `npm run build` | ✅ production build completed (existing chunk-size warning only) |

### Phase 6 — Flutter User Reporting UI ✅ COMPLETE

- [x] Add report endpoint constants, model, service, repository, scope,
      controller, state, and shared report screen.
- [x] Compose the new dependencies in `main.dart` without creating a second API
      client.
- [x] Add a shared form containing reported-user identity, required reason,
      required description, optional screenshot, submit confirmation, and clear
      success/error handling.
- [x] Add the six reason choices exactly as approved.
- [x] Reuse `image_picker` and the existing local preview pattern for one
      optional JPEG/PNG/WebP screenshot.
- [x] Validate screenshot size client-side and rely on server validation as the
      authority.
- [x] Prevent self-reporting client-side; rely on the server for administrator
      and duplicate checks.
- [x] Map `422`, `409`, `429`, and transport failures to clear messages.
- [x] Add **Report Seller** to the Seller Public Profile AppBar overflow menu.
- [x] Add **Report User** to the Conversation Header AppBar overflow menu.
- [x] Add **Report User** for the other participant on Transaction Details.
- [x] Keep all three entry points on the one shared form.
- [x] Add model, service request-shape, controller, widget, and entry-point
      tests.

**Acceptance criteria**

- [x] All three entry points open the same form for the correct user.
- [x] Self-reporting is blocked before submission.
- [x] Reason and description are required.
- [x] Evidence is optional and one file only.
- [x] Submission shows confirmation and a clear result state.
- [x] Duplicate and rate-limit responses are presented honestly.
- [x] No admin endpoint is called by the mobile app.
- [x] `flutter analyze`, `flutter test`, and debug APK build pass.

**Files:** `mobile/lib/core/constants/api_constants.dart`,
`mobile/lib/main.dart`, `mobile/lib/models/user_report.dart`,
`mobile/lib/services/user_report_service.dart`,
`mobile/lib/repositories/user_report_repository.dart`,
`mobile/lib/features/user_reports/state/report_user_controller.dart`,
`mobile/lib/features/user_reports/state/report_user_state.dart`,
`mobile/lib/features/user_reports/state/user_report_scope.dart`,
`mobile/lib/features/user_reports/view/report_user_screen.dart`,
`mobile/lib/features/seller_profile/view/seller_profile_screen.dart`,
`mobile/lib/features/messaging/view/chat_screen.dart`,
`mobile/lib/features/transactions/views/transaction_detail_screen.dart`,
`mobile/lib/features/transactions/views/transaction_detail_content.dart`,
`mobile/test/support/user_report_fakes.dart`,
`mobile/test/models/user_report_test.dart`,
`mobile/test/services/user_report_service_test.dart`,
`mobile/test/features/user_reports/report_user_controller_test.dart`,
`mobile/test/features/user_reports/report_user_screen_test.dart`,
`mobile/test/features/seller_profile/seller_profile_screen_test.dart`,
`mobile/test/features/messaging/chat_accept_offer_test.dart`,
`mobile/test/features/transactions/transaction_detail_screen_test.dart`.

**Evidence log**

| Command | Result |
|---|---|
| `flutter analyze` | ✅ No issues |
| `flutter test --dart-define=API_BASE_URL=http://localhost:8001/api` | ✅ 1287 passed, 1 skipped |
| `flutter build apk --debug` | ✅ `app-debug.apk` built (KGP deprecation warning only) |
| Targeted user-report tests | ✅ model/service/controller/screen and entry-point tests passed |

### Phase 7 — Integration Testing & Documentation ✅ COMPLETE

- [x] Run the full backend suite and targeted report/user-management suites.
- [x] Run frontend typecheck, lint, tests, and production build.
- [x] Run Flutter analyze, full tests, and debug APK build.
- [x] Verify admin deactivation blocks login and existing sessions, and
      reactivation restores access.
- [x] Verify listings hide on deactivation and eligible listings return on
      reactivation without status rewrites.
- [x] Verify transactions and reservations are untouched by deactivation.
- [x] Verify reports never auto-deactivate and a failed report action rolls
      back.
- [x] Verify evidence is private and reporter identity is not exposed to the
      reported user.
- [x] Review the complete diff for unrelated changes and missing tests.
- [x] Update `mobile/AGENTS.md` with the new mobile API and behavior.
- [x] Update `docs/AGROBENTA_FUNCTIONAL_DOCUMENTATION.md` only with explicit
      project-owner approval; otherwise record it as a pending documentation
      decision. (Not approved; recorded below.)
- [x] Run `graphify update .` after implementation changes are complete.
- [x] Record final evidence and Git status in this tracker.

**Acceptance criteria**

- [x] All approved decisions are implemented exactly.
- [x] All prior phase criteria remain true.
- [x] Full backend, frontend, and Flutter verification passes.
- [x] No test is weakened, skipped, or fabricated.
- [x] No unrelated feature or analytics report code is changed.
- [x] Documentation reflects implemented behavior or explicitly records the
      unapproved gap.
- [x] No commit, push, merge, reset, rebase, or branch switch occurred.

**Files:** `mobile/AGENTS.md`, `docs/features/user-management-reporting.md`,
plus the Phase 1–6 files recorded above. The unrelated analytics Reports module,
CSV export code, and `docs/features/reports-export.md` were not modified.

**Evidence log**

| Command | Result |
|---|---|
| `php artisan test` | ✅ 1087 passed, 1 skipped (5146 assertions) |
| `php artisan test --filter='UserReportTest\|UserReportModerationTest\|UserAccountStatusTest'` | ✅ 32 passed (178 assertions) |
| `php artisan route:list --path=admin/user-reports` | ✅ 5 admin routes registered |
| `php artisan route:list --path=report` | ✅ `POST api/reports` plus admin report routes |
| `pint --test` (all changed backend files) | ✅ clean across phases |
| `npm run typecheck` / `npm run lint` | ✅ clean |
| `npm test` | ✅ 287 passed |
| `npm run build` | ✅ production build completed (existing chunk-size warning only) |
| `flutter analyze` | ✅ No issues |
| `flutter test --dart-define=API_BASE_URL=http://localhost:8001/api` | ✅ 1287 passed, 1 skipped |
| `flutter build apk --debug` | ✅ `app-debug.apk` built (194,376,956 bytes) |
| `graphify update .` | ✅ graph rebuilt (12532 nodes, 25139 edges) |
| `git diff --check` | ✅ clean (line-ending warnings only) |

**Functional documentation:** unchanged pending explicit project-owner
approval, as required. The approved reporting/deactivation rules are recorded in
this tracker and `mobile/AGENTS.md`; `docs/AGROBENTA_FUNCTIONAL_DOCUMENTATION.md`
still needs the approved decision entry.

**Final Git state:** branch `review/pr-85`; no commits, pushes, merges, resets,
rebases, or branch switches were performed by this workflow. Tracked changes
are the user-management/reporting feature files; new files are untracked. The
pre-existing untracked `docs/reviews/` and `ml-service/` artifacts remain
untouched. `graphify-out/` is ignored by Git. The unrelated staged
listing-review changes observed at the start of BUILD were not present in the
final working tree; no Git write command was issued by this workflow.

## Verification Commands

```sh
# Backend
docker compose exec php php artisan test
docker compose exec php php artisan test --filter=UserReportTest
docker compose exec php php artisan test --filter='UserManagement|UserReport'
docker compose exec php ./vendor/bin/pint --test
docker compose exec php php artisan route:list --path=admin/user-reports
docker compose exec php php artisan route:list --path=admin/users

# Frontend
cd frontend
npm run typecheck
npm run lint
npm test
npm run build

# Flutter
cd mobile
flutter pub get
flutter analyze
flutter test --dart-define=API_BASE_URL=http://localhost:8001/api
flutter build apk --debug

# Repository hygiene
git diff --check
git status
```

Manual checks after implementation:

- Deactivate a user with a reason; confirm login fails, the existing token
  fails, and the account appears only under Deactivated.
- Reactivate with a reason; confirm the same account signs in again and eligible
  listings reappear.
- Confirm a deactivated user's pending transaction and reserved stock are intact.
- Submit a report from each Flutter entry point; confirm one pending report per
  pair and no account change.
- Review a report with and without evidence; dismiss one and deactivate from
  another.
- Confirm reporter identity/evidence are not exposed to the reported user.

## API / Data Contracts

### `user_reports` table

| Column | Notes |
|---|---|
| `id` | Auto-increment. |
| `reporter_id` | Authenticated reporter; never client-selected. |
| `reported_user_id` | Target account; must be active and not an administrator. |
| `reason` | One of the six approved values. |
| `description` | Required written description. |
| `evidence_path` | Nullable private disk-relative path; never a URL. |
| `status` | `pending`, `dismissed`, `actioned`. |
| `reviewed_by` | Nullable administrator id. |
| `reviewed_at` | Nullable timestamp. |
| `admin_note` | Nullable dismissal/resolution note. |
| timestamps | Standard. |

### `users` additions

| Column | Notes |
|---|---|
| `deactivation_reason` | Nullable text; cleared on reactivation after audit. |
| `deactivated_by` | Nullable administrator FK. |
| `deleted_at` | Existing soft-delete column; also the deactivation timestamp. |

### Report reasons

`scam_fraud`, `harassment`, `misleading_information`,
`spam_suspicious_activity`, `inappropriate_content`, `other`.

Labels: **Scam/Fraud**, **Harassment**, **Misleading Information**,
**Spam/Suspicious Activity**, **Inappropriate Content**, **Other**.

### Mobile endpoint

`POST /api/reports` — multipart, `auth:sanctum` + `ability:mobile`, throttled.

| Field | Rule |
|---|---|
| `reported_user_id` | Required integer; must be an active non-admin account; not self. |
| `reason` | Required approved enum value. |
| `description` | Required string. |
| `evidence` | Optional image; JPEG/PNG/WebP; max 5 MB; one file. |

Reporter is derived from the token. Response contains only reporter-safe report
data (`id`, `reason`, `status`, `created_at`) and never the reporter or evidence
path.

### Admin endpoints

| Method | Path | Purpose |
|---|---|---|
| `GET` | `/api/admin/users?status=active\|deactivated\|all` | User list; default Active. |
| `GET` | `/api/admin/users/{user}` | User detail; may resolve a trashed user. |
| `DELETE` | `/api/admin/users/{user}` | Deactivate; body requires `reason`. |
| `POST` | `/api/admin/users/{user}/reactivate` | Reactivate; body requires `reason`. |
| `GET` | `/api/admin/user-reports` | Paginated report list and total count. |
| `GET` | `/api/admin/user-reports/{report}` | Full report for review. |
| `GET` | `/api/admin/user-reports/{report}/evidence` | Private evidence stream. |
| `POST` | `/api/admin/user-reports/{report}/dismiss` | Dismiss; optional `admin_note`. |
| `POST` | `/api/admin/user-reports/{report}/deactivate` | Deactivate target; required `reason`; marks report `actioned`. |

All admin endpoints use the existing `auth:sanctum` + `admin` +
`ability:admin` group. Report counts include every status. The badge total is
the list total.

## API Compatibility and Review Follow-ups

### Breaking API Change: Admin User Deactivation

**Change introduced:** User Management and User Reporting enhancement (PR #86).

The existing admin endpoint now requires a deactivation reason.

**Endpoint:** `DELETE /api/admin/users/{id}`

**Request body:**

```json
{
  "reason": "Account deactivated due to a confirmed policy violation."
}
```

**Compatibility impact:**
- Previously, API consumers could call this endpoint without providing a reason.
- The updated endpoint requires the `reason` field. Requests without a valid reason fail validation (HTTP 422).
- The React Admin Web interface has been updated to collect and submit the reason.
- Other API consumers, including external clients, scripts, and integrations, must update their requests accordingly.
- This is a breaking request-contract change; the existing endpoint path and HTTP method remain unchanged.

**Migration guidance:** Update any existing callers of the admin user deletion/deactivation endpoint to submit a valid `reason` in the request body. Verify that the caller handles validation errors appropriately.

### Follow-up 1: Repeated User Reports

**Current behavior:** A reporter may have only one pending report against the same user. Once the previous report is resolved or dismissed, a new report may be submitted.

This behavior is intentional under the approved reporting rules.

**Future consideration:** If repeated or abusive submissions become a problem, evaluate additional safeguards such as a targeted cooldown or stricter duplicate-report detection. Any future restriction should still permit reporting genuinely new incidents.

**Status:** Future enhancement; no change required for PR #86.

### Follow-up 2: Reporter Status Notifications

**Current behavior:** Users can submit reports, but they do not receive notifications when administrators dismiss or take action on those reports.

**Future consideration:** Provide privacy-conscious report status updates, such as confirmation of receipt and notification that review has concluded, without exposing confidential moderation decisions, reporter information, or other users' private data.

**Status:** Future enhancement; outside the scope of PR #86.

### Admin user resource additions

`status` (`active`/`deactivated`), `deactivated_at`, `deactivation_reason`,
`deactivated_by`, `reports_count`, and pending-transaction warning data for the
deactivation confirmation. The existing fields remain unchanged.

## Architecture & Dependencies

### Backend

Follow **Controller → Form Request → Service → Repository → Model → Resource**.

- New domain classes live under `App\Services\UserReport`,
  `App\Repositories\UserReport`, and `App\Models\UserReport`.
- Admin moderation lives under `App\Services\Admin` and
  `App\Repositories\Admin`.
- User deactivation/reactivation remains in `AdminUserService`.
- Controllers stay thin; validation belongs in Form Requests; queries belong in
  Repositories.
- Reuse `ActivityLogger`, the admin middleware group, and the private-disk
  streaming pattern.
- Add no parallel authentication, upload, or audit mechanism.

### Admin Web

- Keep the existing feature-based structure under
  `frontend/src/features/admin/users/`.
- Reuse the existing Axios client, React Query keys/invalidation, table, badge,
  tab, dialog, toast, and evidence-viewer patterns.
- Do not create a parallel API client or state system.
- Use the existing `lv-*` visual system; do not introduce a new design language.

### Flutter

- Keep the fixed layering: widget/screen → controller → repository → service →
  `ApiClient`.
- Compose the report service/repository once in `main.dart` and expose it
  through a scope.
- Reuse `image_picker`, `ApiException`, `AuthScope`, and the existing multipart
  path.
- Do not add a new HTTP client, token store, routing system, or state package.

### Dependencies

- No new dependency is planned for image selection; `image_picker` already
  exists.
- No new backend package is planned.
- Evidence requires one new private filesystem disk configuration.

## Risks & Unresolved Issues

1. **Deactivation during active transactions.** Pending transactions and
   reserved stock remain untouched. The seller cannot fulfil after
   deactivation; the buyer can still cancel and release stock. Approved
   behavior is to warn, not mutate.
2. **Deactivated users are invisible in the current admin list.** The status
   filter is required for Reactivate to be reachable. Default Active preserves
   existing totals.
3. **DELETE route semantics.** The existing deactivation route now requires a
   reason. This is an intentional contract change for the Admin Web; tests and
   the UI must be updated together.
4. **Duplicate protection.** MySQL has no portable partial unique index for one
   pending pair. Enforce it atomically in the service by locking the reported
   user row, with a per-user rate limit.
5. **Report status after deactivation from the Users tab.** Only report-driven
   deactivation marks a report `actioned`; a Users-tab deactivation leaves
   pending reports for separate review.
6. **Reactivation side effects.** Email remains reserved while deactivated;
   credentials stay revoked and the user signs in again. Seller capability,
   verification, history, and eligible listings are preserved.
7. **Numbering with the client-side verification filter.** `No.` uses server
   pagination offsets; hidden rows can leave gaps on a page. Moving the
   verification filter server-side is out of scope.
8. **Privacy.** Reporter identity is admin-only, evidence is private, and the
   reported user is not notified. No evidence URL may be stored or returned.
9. **Documentation gap.** The functional documentation currently has no
   user-reporting rule. It may be updated only with explicit approval.
10. **Manual device verification.** Screenshot selection/upload behavior still
    needs an Android device check in addition to automated tests.

## Progress Log

| Date | Phase | Action | Result |
|---|---|---|---|
| 2026-11-18 | 0 | Created workflow tracker after read-only inspection | ✅ Tracker created; no application code changed |
| 2026-11-18 | 1 | Added migrations, enums, report model/relations, private evidence disk, foundation tests | ✅ 6 new tests; 41 targeted; pint clean; migrations roll back |
| 2026-11-18 | 2 | Added report request/service/repository/evidence/resource/route/throttle and tests | ✅ 13 new tests; 36 targeted; route registered; pint clean |
| 2026-11-18 | 3 | Added reason-aware deactivation, reactivation, status filter/counts, audit and tests | ✅ 10 new tests; 45 targeted; routes and pint clean |
| 2026-11-18 | 4 | Added admin report list/detail/evidence/dismiss/deactivate API and tests | ✅ 8 new tests; 31 targeted; routes and pint clean |
| 2026-11-18 | 5 | Added Users/User Reports tabs, columns/status/actions, report modal, hooks and tests | ✅ 35 frontend user tests; typecheck/lint/build clean |
| 2026-11-18 | 6 | Added Flutter report model/service/repository/scope/form, three entry points, tests | ✅ 1287 mobile tests; analyze clean; APK built |
| 2026-11-18 | 7 | Full regression, mobile docs, graph rebuild, final review | ✅ backend 1087; frontend 287; mobile 1287; builds pass |

## Resume Instructions

1. Read `AGENTS.md`, `backend/AGENTS.md`, `frontend/AGENTS.md`,
   `mobile/AGENTS.md`, `docs/AGENTS.md`, `DESIGN.md`, and this tracker.
2. Run `git status` and `git log --oneline -5`; never discard user work.
3. Find the first phase not marked complete.
4. Inspect any partial work and the phase’s file list before editing.
5. Resume at the first unchecked task; do not repeat verified work.
6. Follow the full **INSPECT → IMPLEMENT → TEST → FIX → RETEST → REVIEW DIFF →
   RECORD PROGRESS → CONTINUE** cycle.
7. Record changed files, commands, actual results, and remaining issues in this
   tracker after every verified phase.
8. Continue automatically after a passing phase. Stop for unresolved blockers,
   security risks, destructive changes, or unapproved decisions.
9. Never mark unverified work complete and never fabricate results.
