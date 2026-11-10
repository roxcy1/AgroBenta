# Reverb Integration — Real-Time WebSocket

## Objective & Scope

Add real-time updates to AgroBenta over Laravel Reverb, delivered to Flutter
(mobile) and React (admin) **only while a client is open and connected**. No
FCM/push notifications, typing indicators, or online presence.

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

## Resume Instructions
1. Confirm `git status` and the progress log are current.
2. Read the current (lowest incomplete) phase and its acceptance criteria.
3. Implement only that phase; validate; update the progress log with evidence.
4. Continue to the next phase automatically, or STOP if a stop condition fires.
