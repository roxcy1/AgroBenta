# Digital Receipt Integration

## Objective & Scope

Add a **Digital Livestock Purchase Receipt** for completed transactions. The
buyer sees it automatically after confirming **Received**, may manually save a
high-quality PNG to the device gallery, and may reopen it from completed
history.

Laravel is the authoritative source. The receipt is a record of a completed
sale, **not proof of payment** and not an official/BIR receipt (functional
documentation §6.3).

**In scope:** completed-only party-authorized receipt API; `completed_at` +
immutable `receipt_snapshot`; protection from listing-deletion cascades; Flutter
model/controller/screen; automatic display; buyer-only history entry; manual
Gallery saving on Android/iOS; tests and documentation.

**Out of scope:** payment processing/verification, refunds, PDF/email/share,
seller receipt UI, Admin Web receipts, new Reverb events, status/fulfillment/
permission changes, Gallery saving on web, multi-item transactions, fabricated
unit price/location/attributes.

## Approved Decisions

1. Receipt opens after the buyer’s successful **Confirm Received**; Gallery
   saving is always manual.
2. Laravel owns receipt data via `completed_at` and a historical
   `receipt_snapshot` written at completion.
3. Completed transactions must not be destroyed by a listing-deletion cascade.
4. Receipt API is completed-only and party-authorized; Flutter receipt UI and
   Save action are buyer-only.
5. Wording is a “record of a completed sale”; never “Official Receipt”, “Paid”,
   “Verified payment”, or proof of payment.
6. Android/iOS support Gallery saving; web displays the receipt only.
7. Existing transaction workflows, permissions, fulfillment, inventory and
   Reverb behavior are preserved.

## Safety Constraints

- Read `AGENTS.md`, `backend/AGENTS.md`, `mobile/AGENTS.md`, `docs/AGENTS.md`,
  `DESIGN.md` before editing the relevant scope.
- Backend flow: Controller → Request → Service → Repository → Model → Resource.
- No changes to statuses, fulfillment gates, cancellation, inventory, route
  authorization, or Reverb events.
- Do not weaken/delete tests; do not fabricate results.
- No destructive database operations, secrets, or unrelated refactors.
- Do not commit, push, merge, rebase, reset, or switch branches.
- Do not edit `AGROBENTA_FUNCTIONAL_DOCUMENTATION.md` without PM approval.

## Baseline

- Branch `feature/receipt-integration`; clean at start.
- No receipt implementation existed before this feature.
- Confirmed workflow: `pending → completed | cancelled`; pickup
  `confirmed → preparing → ready_for_pickup → picked_up → completed`; delivery
  `confirmed → preparing → on_the_way → delivered → completed`.
- Only the buyer confirms receipt, after `picked_up`/`delivered`; repeat is
  `409`; stock is consumed once; no refunds/payment status.

## Phase Status

| Phase | Name | Status | Depends on |
|---|---|---|---|
| 0 | Architecture & Workflow Setup | ✅ COMPLETE | — |
| 1 | Laravel Receipt Backend | ✅ COMPLETE | 0 |
| 2 | Flutter Receipt Data & UI | ✅ COMPLETE | 1 |
| 3 | Automatic Receipt Display | ✅ COMPLETE | 2 |
| 4 | Save to Gallery (PNG) | ✅ COMPLETE | 2 |
| 5 | Hardening, Regression & Documentation | ✅ COMPLETE | 1–4 |

## Execution Rules

1. Inspect before editing; never assume a status, field, route, or contract.
2. Implement only the current phase; keep changes minimal and scoped.
3. Run the phase’s tests and verification; fix and retest failures.
4. **A phase may be marked complete only after acceptance criteria are checked
   and its evidence log records files, commands, and actual results.**
5. After a verified phase, update this tracker, then automatically proceed.
6. Stop and report if a decision is outside the approved scope, a security/
   schema/contract change is needed, data loss is possible, a failure cannot be
   resolved safely, or unrelated work is required.
7. Never commit/push/merge/reset. The user owns Git actions.

## Phase 0 — Architecture & Workflow Setup ✅ COMPLETE

- [x] Verify branch, tree, and `AGENTS.md` rules.
- [x] Record inspection findings, approved decisions, constraints, and phases.
- [x] Create this tracker; confirm no app code, migration or dependency changed.
- [x] Define execution and resume rules.

**Evidence:** `docs/features/receipt-integration.md` created; branch
`feature/receipt-integration`; only documentation added.

## Phase 1 — Laravel Receipt Backend ✅ COMPLETE

- [x] Migration adds `transactions.completed_at` (nullable timestamp) and
  `transactions.receipt_snapshot` (nullable JSON).
- [x] `Transaction` exposes the fields and a server-computed `TRX-###`
  reference.
- [x] `TransactionFulfillmentService::confirmReceived()` writes the snapshot and
  completion time inside the existing database transaction.
- [x] `TransactionReceiptService` builds the snapshot and enforces completed-only
  party access.
- [x] `TransactionReceiptResource` returns snapshot values; legacy completed rows
  fall back to live relations + `updated_at`.
- [x] `GET /api/transactions/{id}/receipt` added under existing
  `auth:sanctum` + `ability:mobile`; `404` non-party, `409` non-completed.
- [x] No emails, photos, locations, or payment claims in the payload.
- [x] Listing-deletion protection: `SellerListingService::delete()` refuses
  (`409`) when a completed transaction references the listing. This is the
  chosen mechanism; cancelled history is not blocked.
- [x] Completion response, statuses, fulfillment, cancellation, notifications
  unchanged.

**Acceptance evidence**

- [x] Snapshot and `completed_at` are written atomically with completion.
- [x] Repeat `POST /complete` is `409` and leaves the receipt unchanged.
- [x] Receipt survives a later listing `livestock_type`/`breed` edit.
- [x] Pending/cancelled `409`; non-party `404`; guest `401`; admin token `403`.
- [x] No email fields; no unit price or payment verification invented.
- [x] Inactive listing with a completed transaction cannot be deleted; an
  inactive listing without one still deletes.

**Files:** `backend/database/migrations/2026_11_10_000001_add_receipt_fields_to_transactions.php`,
`backend/app/Models/Transaction.php`,
`backend/app/Repositories/Transaction/TransactionRepository.php`,
`backend/app/Services/Transaction/TransactionReceiptService.php`,
`backend/app/Services/Transaction/TransactionFulfillmentService.php`,
`backend/app/Http/Resources/TransactionReceiptResource.php`,
`backend/app/Http/Controllers/Api/Transaction/TransactionController.php`,
`backend/routes/api.php`,
`backend/app/Services/SellerListing/SellerListingService.php`,
`backend/tests/Feature/Transaction/ReceiptTest.php`.

**Evidence log**

| Command | Result |
|---|---|
| `php artisan test --filter=ReceiptTest` | ✅ 12 passed (73 assertions) |
| `php artisan test --filter='Transaction|SellerListing'` | ✅ 270 passed (1199 assertions) |
| `php artisan test` | ✅ 867 passed (3966 assertions) |
| `php artisan route:list --path=transactions` | ✅ receipt route registered |

## Phase 2 — Flutter Receipt Data & UI ✅ COMPLETE

- [x] `TransactionReceipt` model mirrors the resource; money stays a string.
- [x] Endpoint constant, service and repository method added.
- [x] `TransactionReceiptController` + state handle loading/ready/unavailable/
  failed/retry and disposal.
- [x] `TransactionReceiptScreen` + `TransactionReceiptCard` render reference,
  completion time, buyer, seller, type/breed, quantity, agreed total,
  fulfillment method, preferred payment method, and the honest disclaimer.
- [x] Null/legacy methods render “Not specified” / “Not recorded”; breed is
  omitted when empty.
- [x] Buyer + completed transaction detail shows **View receipt**; seller,
  pending and cancelled do not.
- [x] Shared collection/payment label helpers prevent wording drift.
- [x] No gallery saving or auto-display in this phase.

**Files:** `mobile/lib/models/transaction_receipt.dart`,
`mobile/lib/models/transaction.dart`, `mobile/lib/core/constants/api_constants.dart`,
`mobile/lib/services/transaction_service.dart`,
`mobile/lib/repositories/transaction_repository.dart`,
`mobile/lib/features/receipts/state/*`,
`mobile/lib/features/receipts/widgets/transaction_receipt_card.dart`,
`mobile/lib/features/receipts/view/transaction_receipt_screen.dart`,
`mobile/lib/features/transactions/views/transaction_detail_content.dart`,
`mobile/lib/features/transactions/views/transaction_detail_screen.dart`, plus
model/service/repository/widget tests and `mobile/test/support/transaction_fakes.dart`.

**Evidence:** receipt/model/service/repository suite **25 passed**; analyze
clean. The receipt screen uses only the API payload; no client arithmetic.

## Phase 3 — Automatic Receipt Display ✅ COMPLETE

- [x] After a successful buyer `confirmReceived`, the detail screen pushes the
  receipt automatically.
- [x] Navigation happens once, guarded by the existing in-flight state and the
  server’s `409`; no receipt on failure, `409`, seller actions, cancellation, or
  network error.
- [x] No Reverb dependency; `transaction.updated` never opens a receipt.
- [x] The old confirm-success snackbar is replaced by the receipt.
- [x] Back navigation returns to the completed detail record.
- [x] Existing widget test updated to assert the receipt instead of the snackbar;
  a failed-confirmation test added.

**Files:** `mobile/lib/features/transactions/views/transaction_detail_screen.dart`,
`mobile/test/features/transactions/transaction_detail_screen_test.dart`.

**Evidence:** detail + receipt suites **34 passed**; exactly one
`POST /transactions/1/complete`; no receipt on a failed confirmation; analyze
clean.

## Phase 4 — Save to Gallery (PNG) — ✅ COMPLETE

- [x] Added one maintained dependency, `gal: ^2.3.3` (Dart 3 / Flutter 3.7+;
  Android 21+, iOS 11+).
- [x] `ReceiptPngExporter` captures the receipt `RepaintBoundary` at ~1080 px
  (ratio clamped 1–4) and encodes PNG; `ReceiptGallerySaver` isolates `gal`.
- [x] Save is a manual button; progress state disables repeat taps; the receipt
  stays on screen on success/failure.
- [x] iOS `NSPhotoLibraryAddUsageDescription` added; Android
  `WRITE_EXTERNAL_STORAGE` capped at API 29.
- [x] Web hides the Save action with an honest message; no gallery concept.
- [x] Permission-denied, storage/format/unexpected failures map to clear
  notices; no auto-save.
- [x] Tests inject fake exporter/saver; real PNG capture has its own test.
- [x] Debug APK build verifying the plugin integration.

**Files:** `mobile/pubspec.yaml`, `mobile/pubspec.lock`,
`mobile/lib/features/receipts/services/receipt_gallery_saver.dart`,
`mobile/lib/features/receipts/services/receipt_png_exporter.dart`,
`mobile/lib/features/receipts/view/transaction_receipt_screen.dart`,
`mobile/android/app/src/main/AndroidManifest.xml`,
`mobile/ios/Runner/Info.plist`,
`mobile/test/features/receipts/*`.

**Evidence**

| Command | Result |
|---|---|
| `flutter analyze` | ✅ No issues |
| Receipt + detail + model/service/repo tests | ✅ 50 passed |
| `flutter test ... transaction_receipt_screen_test.dart` | ✅ 6 passed |
| `flutter test ... receipt_png_exporter_test.dart` | ✅ 2 passed (real PNG signature) |
| `flutter build apk --debug` | ✅ `app-debug.apk` built (final rebuild 17.8s) |

## Phase 5 — Hardening, Regression & Documentation — ✅ COMPLETE

- [x] Verify legacy completed rows, listing edits/deletion, offline receipt
  failure/retry, and Reverb coexistence through tests.
- [x] Update `mobile/AGENTS.md` with the receipt endpoint and gallery behavior.
- [x] Functional documentation left unchanged (requires PM approval); recorded
  as a remaining documentation decision.
- [x] Run full Flutter suite, analyze, and debug APK build; review the complete
  diff.
- [x] Run the final full backend suite and record the result.
- [x] Update this tracker with final status, evidence, risks, and Git status.

**Acceptance:** all prior criteria remain true; full suites pass; no weakened
tests; documentation matches behavior; no unrelated changes.

**Files:** `mobile/AGENTS.md` (endpoint, receipt behavior, GAP-11); this tracker.
Functional documentation intentionally unchanged pending PM approval.

**Evidence**

| Command | Result |
|---|---|
| `flutter analyze` | ✅ No issues |
| `flutter test --dart-define=API_BASE_URL=http://localhost:8001/api` | ✅ 1104 passed, 1 skipped |
| `flutter build apk --debug` | ✅ `app-debug.apk` built |
| `pint --test` (changed backend files + migration) | ✅ 9 files pass |
| `php artisan migrate --force` | ✅ receipt migration ran (additive) |
| `php artisan test` | ✅ 867 passed (3966 assertions, 458.90s) |

**Final Git state:** branch `feature/receipt-integration`; no commits, pushes,
merges or resets. Only the receipt feature files, tests, `mobile/AGENTS.md` and
this tracker are modified/untracked. `git diff --check` is clean.

## Verification Commands

```sh
docker compose exec php php artisan test

cd mobile
flutter analyze
flutter test --dart-define=API_BASE_URL=http://localhost:8001/api
flutter build apk --debug
```

Manual: complete a pickup and a delivery sale → receipt opens automatically;
reopen from completed detail → identical values; Save to Gallery → PNG in the
gallery; deny permission → notice, receipt stays; stop Reverb → receipt still
works; seller → no receipt UI.

## Receipt Data Contract

```json
{"success":true,"data":{
  "version":1,
  "reference":"TRX-001",
  "completed_at":"2026-11-10T08:15:00.000000Z",
  "buyer":{"name":"Buyer Name"},
  "seller":{"name":"Seller Name"},
  "listing":{"livestock_type":"Cattle","breed":"Brahman"},
  "quantity":1,
  "total_amount":"48000.00",
  "payment_method":"gcash",
  "collection_method":"seller_arranged_delivery",
  "status":"completed"
}}
```

Rules: money is a display string; no client arithmetic; no emails/photos/
locations; `payment_method` is an unverified preference; null/legacy collection
values render honestly; `completed_at` falls back to `updated_at` for legacy
rows; reference is server-computed.

## Architecture

- Additive read endpoint in the existing transaction group; no new write path.
- Snapshot written in the completion transaction; versioned for evolution.
- Legacy rows use live fallback; no inaccurate backfill.
- Listing deletion guard protects completed receipts.
- Flutter layering: screen → controller → repository → service → `ApiClient`.
- Buyer-only UI; API stays party-authorized.
- PNG capture and gallery writing are injectable interfaces for testability.
- No real-time dependency; no payment claim.

## Risks & Unresolved

1. **Cancelled history:** the deletion guard protects completed transactions
   only, per the approved decision. Cancelled rows can still cascade; revisit if
   history must be fully immutable.
2. **Legacy completed rows:** no snapshot; render live data and `updated_at`.
3. **Manual device verification:** Gallery save is unit-tested with fakes and a
   real PNG-capture test; on-device permission/gallery behavior still needs a
   manual Android/iOS check.
4. **Package platform floor:** `gal` requires Android 21+/iOS 11+; confirm these
   match the shipped targets.
5. **Functional documentation** still describes receipts as handled between the
   parties; changing it needs PM approval. `mobile/AGENTS.md` is updated.
6. **No payment verification exists**, so the receipt must never claim payment.
7. **Migration applied to the dev database** (`php artisan migrate --force`);
   deploy with the normal migration step. It only adds nullable columns.

## Progress Log

| Date | Phase | Action | Result |
|---|---|---|---|
| 2026-11-10 | 0 | Workflow setup | ✅ Tracker created |
| 2026-11-10 | 1 | Receipt migration/snapshot/API/guard | ✅ 12 new tests; 867 backend |
| 2026-11-10 | 2 | Flutter model/controller/screen/history entry | ✅ 25 tests; analyze clean |
| 2026-11-10 | 3 | Auto-display after confirmation | ✅ 34 tests; one POST |
| 2026-11-10 | 4 | PNG capture + gallery + platform config | ✅ 8 receipt tests; APK built |
| 2026-11-10 | 5 | Full regression, docs, final evidence | ✅ 867 backend; 1104 mobile; APK built |

## Resume Instructions

1. Read `AGENTS.md`, `mobile/AGENTS.md`, `DESIGN.md`, and this tracker.
2. Run `git status` and `git log --oneline -5`; never discard user work.
3. Find the first phase not marked complete; read its evidence and inspect
   partial work.
4. Resume at the first unchecked task; do not repeat verified work.
5. Run tests/verification, record files/commands/results, check acceptance only
   when true, update the status and progress log, then continue.
6. If interrupted, record partial results honestly; never mark unverified work
   complete.
