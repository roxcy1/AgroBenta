# Reverb Integration — Real-Time WebSocket

## Objective & Scope

Add real-time updates to AgroBenta over Laravel Reverb, delivered to Flutter
(mobile) and React (admin) **only while a client is open and connected**. No
FCM/push notifications, typing indicators, or online presence.

> Phone push (FCM) was later approved and built separately, outside this
> plan (functional documentation §7, MS-15, 2026-11-11). It reuses the
> `NotificationSent` hook but adds no broadcast event or channel.

In scope: buyer–seller messaging, inquiries, offers, transactions/fulfillment,
and the notification unread badge (mobile), plus admin moderation/activity
dashboards (React).

Out of scope (unapproved): background push, presence channels, client events.

## Phases (execute strictly in order)

### Phase 0 — Prerequisites ✅ COMPLETE
- Install `laravel/reverb`; run `install:broadcasting` (Reverb driver).
- Generate `config/broadcasting.php`, `config/reverb.php`, `routes/channels.php`;
  register channels in `bootstrap/app.php`.
- Add `REVERB_*` placeholders to `.env.example`; keep secrets in `.env`.
- Verify: `php artisan about` (Broadcasting: reverb),
  `php artisan config:show broadcasting`; no events/listeners/clients added.

### Phase 1 — Server Infrastructure ✅ COMPLETE
- Configure `REVERB_*`, `BROADCAST_CONNECTION=reverb`, `QUEUE_CONNECTION=redis`.
- Enable the `reverb` service (listen `0.0.0.0:8080`, publish `8083`); add a
  Redis `queue` worker service; preserve existing services/ports.
- Verify phpredis→Redis connectivity; single-instance Reverb (scaling off).
- Verify a raw WebSocket handshake succeeds and the queue worker stays up.

### Phase 2 — Channel Authorization + First Event ✅ COMPLETE
- `routes/channels.php`: `user.{id}` (self-only) and `admin.{id}` (admin-only).
- `/broadcasting/auth` switched from the session `web` middleware to
  `auth:sanctum` (bearer-token channel auth) via `withBroadcasting(...)`.
- `App\Events\MessageSent` (queued + after-commit) dispatched from
  `MessagingService::sendMessage()` to `private-user.{receiver_id}`.
- Evidence: `MessageBroadcastTest` (6 tests) passes; 843 full-suite tests pass.

### Phase 3 — Extend Events (backend) + Flutter Client ✅ COMPLETE
- ✅ Backend: `InquiryCreated`, `OfferCreated`, `OfferUpdated`,
  `TransactionCreated`, `TransactionUpdated` events dispatched after commit at
  the service mutation points; `RealtimeEventTest` (4 tests) passes.
- ✅ Flutter: `pusher_reverb_flutter: ^0.0.10` (maintained, custom host/port,
  bearer-token authorizer, auto-reconnect, Web/Android/iOS). Wrapped by
  `lib/core/realtime/` (`RealtimeClient`/`PusherReverbClient`,
  `RealtimeController`, `RealtimeEvent`). `main.dart` connects on sign-in,
  disconnects on sign-out, and re-fetches notifications/inbox on events.
- Evidence: `flutter analyze` clean; 11 realtime tests pass; mobile suite
  1049 passed / 1 skipped at the time (the one date-rollover flake in
  `make_offer_screen_test.dart`, unrelated to realtime, has since been fixed).

### Phase 4 — Notifications Badge + Admin ✅ COMPLETE
- Mobile badge: a database-notification listener (`AppServiceProvider`) broadcasts
  `NotificationCreated` to `private-user.{id}`, covering notifications with no
  domain event (admin approval/rejection). `main.dart` re-fetches the unread
  count on every realtime event.
- Admin: shared `admin` channel (`routes/channels.php`, any admin). `ActivityLogger`
  broadcasts `ActivityRecorded` to `private-admin` on every audited action.
  React (`laravel-echo` + `pusher-js`) invalidates the affected react-query keys
  from `useAdminRealtime` (mounted once in `AdminLayout`).
- Evidence: `Phase4BroadcastTest` (4 tests); React typecheck/lint/203 tests/build pass.

### Phase 5 — Hardening & Tests ✅ COMPLETE
- Reconnect reconciliation: the Flutter client exposes a `connected` stream;
  `main.dart` re-fetches notifications/inbox when the socket reconnects, so
  events missed while offline are recovered.
- Duplicate prevention: channel subscription is guarded (same name = no-op) and
  the controller's `start` is idempotent.
- Queue-failure tolerance: `BroadcastContractTest` pins `ShouldQueue` +
  `ShouldDispatchAfterCommit` on every event, so a Reverb outage cannot fail the
  request and a rollback cannot broadcast a phantom.
- Channel-authorization tests cover `user.{id}`, `admin.{id}` and the shared
  `admin` channel.
- Docs: this file, `mobile/AGENTS.md` GAP-20, and `README.md` updated.

## Reliability Fixes (post-integration, 2026-11-27)

A later inspection found that browser clients never received any event and
that event-driven refreshes could blank screens or drop events. Fixed in six
ordered phases (01–06).

### Fix Phase 01 — Restore connectivity (C1, M2) ✅ COMPLETE
- `config/cors.php` now covers `broadcasting/auth`. Before, the browser blocked
  every channel authorization after the preflight, so the Admin Web and Flutter
  Web subscribed to nothing. Origins, `auth:sanctum` and the channel callbacks
  are unchanged (`tests/Feature/Realtime/BroadcastingCorsTest.php`).
- Flutter logs socket state, confirmed subscriptions and authorization errors
  (channel + HTTP status, never the token or payload). `connected` now emits
  `true` when the user channel subscription succeeds, not when the socket
  opens, so the catch-up re-fetch runs once events are live.
- React logs socket state and subscription errors (type + HTTP status only) and
  re-fetches on a confirmed `private-admin` (re)subscription
  (`frontend/src/lib/realtime.test.ts`).

### Fix Phase 02 — Reliable event handling (H1, H2) ✅ COMPLETE
- `mobile/lib/core/realtime/refresh_coalescer.dart`: at most one background
  refresh at a time; events during a refresh or an owner load produce exactly
  one trailing refresh (never dropped, never overlapping, no loop).
- Used by the chat thread, chat offers, notifications, active inquiries,
  transaction detail, seller dashboard, seller verification, seller listings
  and marketplace controllers. Background refreshes keep content on screen and
  leave it untouched on failure.
- The open chat no longer shows its full-screen spinner per message, keeps
  in-flight optimistic bubbles, never duplicates a sent message, and marks
  newly received messages read only while its route is on top and the app is
  in the foreground. Notifications merge page 1 in front of deeper pages
  instead of resetting the scroll depth; `loadMore` de-duplicates by id.
- Tests: `refresh_coalescer_test.dart`, `realtime_background_refresh_test.dart`.

### Fix Phase 03 — Queue pickup latency (M1) ✅ COMPLETE
- The idle worker slept 3 s between polls (`--sleep=3`, `block_for` null).
  Now the redis connection uses `block_for` (default 1 s,
  `REDIS_QUEUE_BLOCK_FOR`) and the worker runs with `--sleep=0`: it waits on a
  blocking pop that wakes on push. 1 s rather than longer because the pop is
  not interrupted by SIGTERM and `docker compose stop` here allows only ~2 s;
  with 5 s the worker was SIGKILLed (exit 137) instead of stopping cleanly.
- Measured end to end (queued dispatch → worker → Reverb → WebSocket
  subscriber, random 0.5–4 s idle gaps): before p50 2023 ms / mean 1770 ms /
  max 2987 ms (12 events); after p50 6 ms / mean 13 ms / max 153 ms (20 events).
  Idle worker CPU < 0.5%; graceful stop exit 0 in ~1.2–1.5 s.
- Applied with `docker compose up -d --no-deps queue` (the command changed) and
  a worker restart for the config.

### Fix Phase 04 — Mobile connection reliability (M3) ✅ COMPLETE
- Heartbeat: WebSocket ping frames every 20 s on native
  (`PusherReverbClient.heartbeatInterval`), so a half-open socket is closed and
  the package's automatic reconnect (exponential backoff, capped at 30 s) runs.
  Browsers keep their own socket alive; the setting is ignored on web.
- Resume: `main.dart` observes the app lifecycle and, only after a real
  backgrounding (`paused`/`hidden`, not a dialog's `inactive`), calls
  `RealtimeController.resume()`. A live user channel emits `connected = true`
  (open screens re-fetch silently); a lost one reconnects now; a connection
  attempt already in progress is left to finish.
- Reconnect/resume resync also covers the notification list and marketplace
  (only if they were loaded; a never-opened list is not fetched, so a buyer no
  longer spends a 403 on seller listings).
- Session safety: the stale-socket-id fast path was removed and the package's
  `socketId` is cleared on disconnect; no second socket is opened while the
  package has a reconnect scheduled (it cannot be cancelled); a socket that
  reconnects after sign-out is closed; frames for channels this session does
  not own are dropped; channels are unsubscribed before the socket closes (the
  package otherwise raised "Cannot add event after closing" on every sign-out).

### Fix Phase 05 — Admin coverage (M4) ✅ COMPLETE
- `adminRealtimeInvalidation.ts` maps every `ActivityAction` prefix
  (underscore-anchored, so `user_logged_in` never matches `user_report_`):
  `admin_user_*` → Users + Reports analytics; `user_report_*` → report queue +
  Users; listing/offer/transaction/verification → their lists + Reports
  analytics; logins → activity feed + dashboard only.
- Report submission writes no audit row, so it never broadcast. New
  `App\Events\UserReportSubmitted` (`private-admin`, `user-report.submitted`,
  payload `report_id` only) is dispatched after commit from
  `UserReportService::create`; the Admin Web refreshes the report queue and the
  Users report counts. Audit-log semantics are unchanged
  (`tests/Feature/Realtime/UserReportBroadcastTest.php`).
- The Admin Web no longer re-fetches every query on its first subscription
  (the pages have just loaded); re-subscriptions still re-fetch.

### Fix Phase 06 — End-to-end verification ✅ COMPLETE (local stack)
Run against an isolated stack so no development data is written:

1. Create a throwaway database (`agrobenta_e2e`) and grant the app user on it.
2. Run every command below with these overrides (they win over `.env`):
   `DB_DATABASE=agrobenta_e2e REDIS_QUEUE=e2e CACHE_STORE=array
   SESSION_DRIVER=array MAIL_MAILER=array FCM_CREDENTIALS= LOG_CHANNEL=stderr`.
   First confirm `DB::connection()->getDatabaseName()` is `agrobenta_e2e`,
   then `php artisan migrate --force` (never `migrate:fresh`).
3. Start ids at 900000 (`ALTER TABLE users/listings AUTO_INCREMENT=900000`) so
   `private-user.{id}` cannot collide with a development account's channel.
4. Seed an admin, an approved seller, two buyers and one active listing, and
   write their ids plus throwaway tokens to a fixture file:
   `{seller, buyer, buyer2, admin: {id, token}, listing_id}`.
5. Start a one-off app server on a published port and a one-off worker, both
   with the overrides: `php -S 0.0.0.0:8090 -t .
   ../vendor/laravel/framework/src/Illuminate/Foundation/resources/server.php`
   from `public/` (not `artisan serve`, which re-reads `.env`), and
   `php artisan queue:work redis --sleep=0 --tries=3 --timeout=60`.
6. Server-side matrix (raw Pusher clients + the Admin Web's own
   `laravel-echo`/`pusher-js`, all authorized through the real
   `/broadcasting/auth`); then the Flutter client:
   `flutter test test/e2e/realtime_live_test.dart --dart-define=E2E_FIXTURE=<fixture>
   --dart-define=API_BASE_URL=http://localhost:8090/api
   --dart-define=REVERB_WS_URL=ws://localhost:8083` (it restarts the `reverb`
   container once to test recovery).
7. Check `queues:e2e` is empty and `agrobenta_e2e.failed_jobs`, then drop the
   database, remove the containers and delete the `queues:e2e*` keys.

Results (2026-11-27): matrix 44/44 (messaging, inquiry, offer, accept →
transaction + inventory, fulfillment, report, admin moderation, 15 rapid
messages in order, 10 concurrent sends exactly once, 401/403/forged-signature
refusals, no cross-account delivery); Flutter live 9/9 (live chat + read
receipts, notifications, transaction detail, marketplace, Reverb outage →
reconnect → exactly one resubscription → missed message recovered, resume
resync, 35 s idle, account switch, refused cross-user subscription). One
failed job, by design: the `MessageSent` dispatched while Reverb was down
exhausted its three immediate retries; the client recovered it over REST.

## Dependencies
- Phases are strictly sequential: 0 → 1 → 2 → 3 → 4 → 5.
- Phase 2 depends on 0+1; Phase 3 depends on 2 (channel auth must exist first);
  Phase 4 depends on 3 (mobile subscribe pattern); Phase 5 depends on all.

## Acceptance Criteria (per phase)
- [Phase 2]: private channel rejects a non-owner; `MessageSent` round-trips to
  the correct `private-user.{id}` channel.
- [Phase 3]: each event reaches the correct counterparty channel; offline
  messages recovered on reconnect; no duplicate rows.
- [Phase 4]: unread badge updates live; admin lists refresh on a real-time event.
- [Phase 5]: no regression in the full Laravel suite; new tests pass.

## Verification Commands
- Backend: `docker compose exec php php artisan test`
- Config: `php artisan about`, `php artisan config:show broadcasting`,
  `php artisan config:show reverb`, `php artisan config:show queue`
- Docker: `docker compose config`, `docker compose ps`,
  `docker compose logs reverb queue`
- WebSocket handshake: raw WS connect to `ws://localhost:8083/app/{key}?...`
  (expect `pusher:connection_established`)
- Redis: `docker compose exec redis redis-cli CLIENT LIST`
- Mobile (Phase 3+): `flutter analyze`, `flutter test`

## Current Verified Progress
- Phase 0 ✅ COMPLETE (2026-11-09)
- Phase 1 ✅ COMPLETE (2026-11-10)
- Phase 2 ✅ COMPLETE (2026-11-10) — channel auth + `MessageSent`
- Phase 3 ✅ COMPLETE (2026-11-10) — backend events + Flutter client
- Phase 4 ✅ COMPLETE (2026-11-10) — notification broadcast + admin realtime
- Phase 5 ✅ COMPLETE (2026-11-10) — hardening, reconcile, docs

All six phases complete. Ready for final review.

## Risks & Unresolved Decisions
- Flutter client library: **resolved** — `pusher_reverb_flutter ^0.0.10`
  (approved; verified against the package source and the live Reverb server).
- React client library: `laravel-echo ^2.6.3` + `pusher-js ^8.6.0`.
- Admin realtime uses a shared `admin` channel (any authenticated admin), plus
  `ActivityRecorded`; the mobile badge uses `NotificationCreated`.
- Transactions tab (My Purchases/My Sales) is per-screen and not session-scoped,
  so it refreshes on pull-to-refresh / tab re-selection rather than on a live
  event; the notification badge refreshes live.
- Client-facing WSS (TLS) + Android cleartext `ws://` handling (documented in
  `backend/.env.example`).
- Pre-existing `composer audit` advisories (9) — unrelated, tracked separately.

## Implementation Progress Log
| Date | Phase | Action | Result |
|---|---|---|---|
| 2026-11-09 | 0 | Install Reverb + generate broadcasting config | ✅ 833 tests pass |
| 2026-11-10 | 1 | Reverb server + Redis queue worker | ✅ WS handshake OK; 833 tests pass |
| 2026-11-10 | 2 | `user.{id}`/`admin.{id}` auth + `MessageSent` | ✅ 6 new tests pass; 843 total |
| 2026-11-10 | 3 | Inquiry/offer/transaction events | ✅ 4 new tests pass; 843 total |
| 2026-11-10 | 3 | Flutter realtime client (`pusher_reverb_flutter`) | ✅ 11 tests; analyze clean |
| 2026-11-10 | 4 | Notification broadcast + shared admin channel | ✅ 4 tests; 855 backend total |
| 2026-11-10 | 4 | React Echo client + invalidation | ✅ typecheck/lint/203 tests/build |
| 2026-11-10 | 5 | Reconnect reconcile + resilience contract | ✅ 855 backend; mobile 1050 pass |
| 2026-11-27 | Fix 01 | CORS for `broadcasting/auth`; subscription logging | ✅ 8 CORS tests; 7 React + 6 Flutter tests |
| 2026-11-27 | Fix 02 | Coalesced background refresh in nine controllers | ✅ 7 coalescer + 43 controller tests |
| 2026-11-27 | Fix 03 | Blocking queue pop (`block_for` 1 s, `--sleep=0`) | ✅ p50 2023 → 6 ms; graceful stop |
| 2026-11-27 | Fix 04 | Heartbeat, resume check, session-safe reconnect | ✅ unit tests + live 9/9 |
| 2026-11-27 | Fix 05 | Admin invalidation map; `UserReportSubmitted` | ✅ 3 backend + 14 React tests |
| 2026-11-27 | Fix 06 | Isolated E2E stack: event matrix + Flutter live test | ✅ 44/44 + 9/9; 1 expected failed job |

## Resume Instructions
1. Confirm `git status` and the progress log are current.
2. Read the current (lowest incomplete) phase and its acceptance criteria.
3. Implement only that phase; validate; update the progress log with evidence.
4. Continue to the next phase automatically, or STOP if a stop condition fires.
