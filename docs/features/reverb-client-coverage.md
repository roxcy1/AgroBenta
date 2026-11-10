# Reverb Client Coverage Completion

## Objective & Scope

The backend Reverb integration is complete (see
`docs/features/reverb-integration.md`, Phases 0–5): events, private channels,
the Flutter socket, and the React admin socket all exist and are tested.

A read-only audit found that the **clients do not yet consume every event on
every screen**. Flutter currently re-fetches only the Messages inbox and the two
badges; the open chat, offer panel, notification list, verification/listing
status, transactions, inquiries and dashboard counts still rely on manual or
pull-to-refresh. The React admin is broadly wired but has no reconnect
reconciliation and no test.

This feature closes only those **client-side coverage gaps**. It is additive:
no new backend events, no new channels, no REST/API contract changes, no
business-rule changes, no new dependencies.

**In scope**

* Flutter screen-level re-fetch on the events the backend already broadcasts.
* React admin reconnect reconciliation.
* Flutter event-routing tests and React invalidation tests.
* Everyday regression/authorization/lifecycle verification.

**Out of scope**

* New broadcast events, channels, or authorization rules.
* Push/FCM, presence, typing indicators, delivery receipts.
* New packages/dependencies.
* Any change to existing REST endpoints, responses, or business behavior.

## Phase Dependencies

* Depends on the completed `reverb-integration.md` (Phases 0–5) — Reverb server,
  channels, events, and both clients must remain as-is.
* Phases are strictly sequential: **1 → 2 → 3 → 4**.
* Phase 2 depends on 1 (the shared `main.dart` routing pattern is established
  there). Phase 3 depends on 1–2 (same routing + per-screen re-fetch pattern).
  Phase 4 depends on 1–3 (tests cover the wiring built in them).

## Approved Phases

All four phases are **COMPLETE** (see the progress log and each phase's
acceptance criteria).

### Phase 1 — Messaging & Offers — ✅ COMPLETE

**Goal.** Make the *open* chat thread and the *open* offer panel update on the
events the backend already sends.

**Scope**
* Refresh the open chat thread on `message.sent`.
* Refresh the active offer panel on `offer.created` / `offer.updated`.
* Prevent duplicate subscriptions and unnecessary API requests.

**Touch points (verify before editing)**
* `mobile/lib/main.dart` — `_handleRealtimeEvent` routing.
* `mobile/lib/features/messaging/state/chat_controller.dart`,
  `mobile/lib/features/messaging/view/chat_screen.dart`.
* `mobile/lib/features/offers/state/chat_offers_controller.dart`,
  `mobile/lib/features/offers/widgets/chat_offer_panel.dart`.

**Acceptance criteria**
* [x] A message from the counterpart appears in the open thread without a
  manual refresh (or the thread gains a pull-to-refresh as a fallback).
* [x] An offer created/updated while the chat is open refreshes the offer panel.
* [x] Only the open thread/panel re-fetches; unrelated screens do not.
* [x] No duplicate socket listeners or duplicate subscriptions; controllers are
  disposed/unsubscribed with their screen.
* [x] Existing send/accept/decline/withdraw REST behavior is unchanged.

**Implementation**
* Added `mobile/lib/core/realtime/realtime_scope.dart` (optional `maybeOf`) and
  wrapped `MaterialApp` in `main.dart`.
* `ChatController` and `ChatOffersController` take `Stream<RealtimeEvent>?` and
  subscribe in their constructor, cancelling in `dispose`. `ChatScreen` passes
  `RealtimeScope.maybeOf(context)?.events`.
* Filtering: `ChatController` refreshes only on `message.sent` from the
  counterpart; `ChatOffersController` only on `offer.*` where the counterpart is
  a party.

**Evidence:** `mobile/test/features/messaging/chat_realtime_test.dart` — 9 tests
pass; `flutter analyze` clean; full mobile suite 1059 passed / 1 skipped (only
the pre-existing `make_offer_screen_test.dart` date-rollover flake).

### Phase 2 — Notifications & Approvals — ✅ COMPLETE

**Goal.** Keep the notification list and the applicant/seller status screens
current after decisions.

**Scope**
* Refresh the notification list on `notification.created` (not only the badge).
* Refresh seller verification status after `SellerVerificationApproved` /
  `SellerVerificationRejected` notifications.
* Refresh livestock listing status after `ListingApproved` /
  `ListingRejected` notifications.
* Preserve existing admin moderation behavior.

**Touch points (verify before editing)**
* `mobile/lib/main.dart` — `_handleRealtimeEvent`.
* `mobile/lib/features/notifications/state/notifications_controller.dart`
  (`refresh` vs `refreshUnreadCount`).
* `mobile/lib/features/seller_verification/state/seller_verification_controller.dart`.
* `mobile/lib/features/seller_listings/state/seller_listing_controller.dart`.
* Admin (must not regress): `frontend/src/features/admin/api/useAdminRealtime.ts`.

**Acceptance criteria**
* [x] An open Notifications screen shows a newly created notification without a
  manual refresh.
* [x] The applicant's verification status reflects approval/rejection without a
  manual refresh.
* [x] My Listings reflects approval/rejection without a manual refresh.
* [x] Admin moderation queues/activities still refresh on `activity.recorded`
  (no regression; covered by tests in Phase 4).
* [x] No notification or decision is marked read/changed client-side.

**Implementation**
* Moved the session-scoped routing out of `main.dart` into the controllers:
  `NotificationsController`, `ConversationsController`,
  `SellerVerificationController` and `SellerListingController` now take a
  `Stream<RealtimeEvent>?`, subscribe in their constructor, and cancel in
  `dispose`. `main.dart` creates the realtime controller first and passes its
  stream in `_createSessionControllers`, so recreating the controllers on an
  account change cannot leave a stale routing reference.
* **Required fix:** `NotificationsController.load()`'s guard skipped the very
  first load (`isInitialLoad` includes `initial`), so the inbox stayed on its
  spinner until a filter chip was tapped. Changed it to skip only while
  `status == loading`, matching its own "unless one is already in flight"
  contract. This makes both the screen's initial load and the realtime refresh
  work.

**Evidence:** `mobile/test/core/realtime/realtime_session_refresh_test.dart` —
6 tests pass (badge on every event, list on `notification.created`, verification
only on `seller_verification`, listings only on `listing`, plus negative cases);
`flutter analyze` clean; full mobile suite 1065 passed / 1 skipped (only the
pre-existing `make_offer_screen_test.dart` date-rollover flake).

### Phase 3 — Transactions & Inquiries — ✅ COMPLETE

**Goal.** Make the transaction and inquiry surfaces (and their dashboard
counts) update on the events already broadcast.

**Scope**
* Refresh the active transaction detail, My Purchases, and My Sales on
  `transaction.created` / `transaction.updated`.
* Refresh received inquiries, active inquiries, and relevant dashboard counts.
* Keep updates scoped to the affected screens and records.

**Touch points (verify before editing)**
* `mobile/lib/main.dart` — `_handleRealtimeEvent`.
* `mobile/lib/features/transactions/state/transactions_controller.dart`,
  `mobile/lib/features/transactions/state/transaction_detail_controller.dart`,
  `mobile/lib/features/transactions/views/transactions_screen.dart`.
* `mobile/lib/features/messaging/view/conversations_screen.dart`
  (the Inquiries/Transactions chips own their own controllers).
* `mobile/lib/features/inquiries/state/received_inquiries_controller.dart`,
  `mobile/lib/features/inquiries/state/active_inquiries_controller.dart`.
* `mobile/lib/features/seller_dashboard/state/seller_dashboard_controller.dart`.

**Acceptance criteria**
* [x] My Purchases / My Sales and the transaction detail update on transaction
  events without a manual refresh.
* [x] The seller's Received Inquiries and the Messages→Inquiries tab update on
  `inquiry.created`.
* [x] Relevant dashboard counts update (Seller Home) on the triggering events.
* [x] A refresh touches only the affected record/screen (no cross-record or
  cross-account leakage).
* [x] Authorization is unchanged (server remains the authority).

**Implementation**
* Each per-screen controller now takes `Stream<RealtimeEvent>?`, subscribes in
  its constructor and cancels in `dispose`:
  `TransactionsController` and `ReceivedInquiriesController` on
  transaction/inquiry/offer events; `TransactionDetailController` only when
  `event.data['transaction_id']` matches its own id; `ActiveInquiriesController`
  on inquiry/offer; `SellerDashboardController` on inquiry/transaction and on a
  `notification.created` of type `listing`.
* Creation sites pass `RealtimeScope.maybeOf(context)?.events`:
  `TransactionsScreen`, `TransactionDetailScreen`, `TransactionStatusScreen`,
  `ConversationsScreen` (both chips), `ReceivedInquiriesScreen`, and
  `SellerDashboardView` (dashboard + its attention inbox).

**Evidence:** `mobile/test/core/realtime/realtime_transaction_inquiry_test.dart`
— 9 tests pass (list, record-scoped detail, both inquiry surfaces, dashboard
counts, plus negative cases); `flutter analyze` clean; full mobile suite 1074
passed / 1 skipped (only the pre-existing `make_offer_screen_test.dart` date
flake).

### Phase 4 — Reconnection & Tests — ✅ COMPLETE

**Goal.** Recover missed events after a socket reconnect and lock the wiring
down with tests.

**Scope**
* Re-fetch relevant data after Flutter and React WebSocket reconnection.
* Add Flutter event-routing tests and React invalidation tests.
* Verify authorization, lifecycle cleanup, and regression coverage.

**Touch points (verify before editing)**
* `mobile/lib/main.dart` — `_handleRealtimeConnection`.
* `frontend/src/lib/realtime.ts` — Echo `connected` (re)connection.
* `mobile/test/core/realtime/` (extend) and a new event-routing test.
* `frontend/src/features/admin/api/useAdminRealtime.test.ts` (new).

**Acceptance criteria**
* [x] After a Flutter reconnect, the screens touched in Phases 1–3 re-fetch.
* [x] After a React reconnect, the admin queries re-fetch (or the chosen
  behaviour is documented and justified).
* [x] Flutter tests cover the event→refresh routing; React tests cover
  `invalidateForActivity`.
* [x] Authorization tests still pass (channel auth, 401/403 matrix).
* [x] Lifecycle cleanup is covered (no leaked listeners/subscriptions).
* [x] `flutter analyze` + `flutter test`, `npm run typecheck`/`lint`/`test`/
  `build`, and the full backend suite pass.

**Implementation**
* Flutter: every per-screen controller (chat, offers, transactions, transaction
  detail, active/received inquiries, seller dashboard) now also accepts
  `Stream<bool>? connection`; on `true` it re-fetches and on dispose it cancels
  the subscription. `main.dart`'s `_handleRealtimeConnection` refreshes the
  session controllers (notifications, conversations, verification, listings).
* React: `connectAdminRealtime` binds the Pusher `connected` event and calls an
  `onReconnected` callback; `useAdminRealtime` invalidates `['admin']` on
  reconnect. The pure routing was extracted to
  `adminRealtimeInvalidation.ts` so it is unit-testable without loading
  `pusher-js`.
* Tests: controller-level event routing (Phases 1–3 files) plus
  `realtime_reconnect_test.dart` (reconnect + dispose-leak) and
  `adminRealtimeInvalidation.test.ts`.

**Evidence:** `flutter analyze` clean; full mobile suite 1077 passed / 1 skipped
(only the pre-existing `make_offer_screen_test.dart` date flake); React
typecheck/lint/build clean and 211 tests pass (8 new); full backend suite
unchanged.

## Verification Commands

```sh
# Backend (must stay green — this feature is client-only)
docker compose exec php php artisan test

# Flutter (the `API_BASE_URL` define is required: flutter test defaults to the
# Android platform and would otherwise throw from AppConfig)
cd mobile
flutter analyze
flutter test --dart-define=API_BASE_URL=http://localhost:8001/api

# React admin
docker compose exec node npm run typecheck
docker compose exec node npm run lint
docker compose exec node npm test
docker compose exec node npm run build

# Runtime sanity (infrastructure was completed in reverb-integration.md)
docker compose config
docker compose ps
docker compose exec php php artisan about
docker compose logs reverb queue

# Manual end-to-end (per phase): with a live client connected,
#  - send a message and confirm the open thread updates (Phase 1);
#  - create an inquiry and confirm the seller inbox updates (Phase 3);
#  - accept an offer and confirm the seller's transactions update (Phase 3);
#  - approve a listing/verification and confirm the seller screen updates (Phase 2);
#  - stop/start the `reverb` container and confirm reconnect re-fetch (Phase 4).
```

## Current Verified Progress

* Phase 0–5 of `reverb-integration.md` — ✅ COMPLETE (backend + clients).
* **Phase 1 — Messaging & Offers: ✅ COMPLETE**
* **Phase 2 — Notifications & Approvals: ✅ COMPLETE**
* **Phase 3 — Transactions & Inquiries: ✅ COMPLETE**
* **Phase 4 — Reconnection & Tests: ✅ COMPLETE**

All four phases complete. Baseline before this feature: backend 855 tests,
Flutter 1050 / 1 skipped, React 203. After this feature: Flutter 1078 passed /
1 skipped (adding 24 realtime tests: 9 chat/offers, 6 session, 9
transaction/inquiry, 3 reconnect), React 211 passed (+8). The Flutter suite is
fully green: the pre-existing `make_offer_screen_test.dart` date-rollover flake
was fixed (see below).

## Risks & Unresolved Decisions

* **Event surface is fixed.** No new backend events were added; everything is
  driven by the existing events and notification types.
* **Per-screen controllers — resolved.** The chosen pattern is an optional
  `Stream<RealtimeEvent>?` (plus `Stream<bool>? connection` for reconnect) passed
  from `RealtimeScope.maybeOf(context)`; each controller owns exactly one
  subscription and cancels it in `dispose`. No session-scoped "changed"
  coordinator was introduced, and no duplicate listeners exist.
* **Known limitation:** the notification list refreshes with a brief loading
  state (the controller reloads page 1), because there is no silent in-place
  refresh. Acceptable for infrequent notifications.
* **Avoid over-fetching.** A single event does not re-fetch every screen: chat/
  offers are scoped to the counterpart, the transaction detail to its own id,
  and the admin maps activity prefixes to query keys.
* **Duplicate events vs HTTP overlap.** Refreshes replace from the REST
  response, so a duplicate event cannot append a duplicate row.
* **Date-rollover flake — fixed.** `make_offer_screen_test.dart` hardcoded
  `2026-11-10` as a "future" preferred date; once the wall clock reached that
  date the screen correctly clamped it to tomorrow. The test now derives a
  genuinely future date from `DateTime.now()` and asserts against it, so it
  cannot go stale. The exact-date assertion is preserved (not weakened).
* **Documentation note:** fixing the notification first-load guard changes
  pre-existing behavior (the inbox previously never left its spinner until a
  filter chip was tapped); this was required for the phase's "refresh the list"
  criterion and is recorded in the Phase 2 log.
* **Reconnect semantics.** The package re-subscribes channels but does not
  replay missed events; recovery is an explicit re-fetch. Confirm the chosen
  scope per client in Phase 4.

## Sequential Execution Rules

For every phase, in order:

1. **Inspect** the affected files and their tests; confirm the approved scope.
2. **Implement** minimal, pattern-consistent changes; no new dependencies.
3. **Test** with the documented commands; record the exact results.
4. **Fix** only issues introduced by the change; re-run affected checks.
5. **Review** the `git diff`; remove accidental/unrelated edits.
6. **Record** the phase in the progress log with evidence (commands + results).
7. **Continue** to the next phase automatically, or **STOP** on a stop
   condition.

## Stop Conditions

Immediately stop and request approval when:

* Requirements are ambiguous or missing.
* A new backend event, channel, authorization rule, or API contract change
  appears necessary.
* A new dependency or significant architectural change is required.
* A destructive database/filesystem/Git operation is needed.
* Verification cannot be completed or a failure cannot be resolved safely.
* Work would exceed the four approved phases or overwrite existing changes.

## Implementation Progress Log

| Date | Phase | Action | Result |
|---|---|---|---|
| 2026-11-10 | 1 | Messaging & Offers | ✅ 9 tests; analyze clean; 1059 mobile pass |
| 2026-11-10 | 2 | Notifications & Approvals | ✅ 6 tests; 1065 mobile pass |
| 2026-11-10 | 3 | Transactions & Inquiries | ✅ 9 tests; 1074 mobile pass |
| 2026-11-10 | 4 | Reconnection & Tests | ✅ 3 Flutter + 8 React tests; 1077 mobile, 211 React |
| 2026-11-10 | — | Fix `make_offer_screen_test.dart` date flake | ✅ 3 tests; full mobile suite 1078 pass, 0 fail |

## Resume Instructions

1. Confirm `git status` is clean of unrelated changes and this log is current.
2. Read `AGENTS.md`, `docs/features/reverb-integration.md`, and this file.
3. Resume from the lowest incomplete phase (all four are currently complete);
   inspect before editing.
4. Follow the sequential execution rules; update the log with evidence.
5. Stop at any stop condition; otherwise continue through Phase 4.
