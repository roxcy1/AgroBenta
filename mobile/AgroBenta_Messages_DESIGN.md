# AgroBenta Mobile — Messages Screen Design (WebSocket)

## 1. Purpose

This document specifies the **Messages** inbox screen for the AgroBenta Flutter mobile application, based on the supplied screenshot. The screen should list real conversations and support real-time message updates through the project's approved WebSocket implementation.

The screenshot is a visual reference. Names, avatars, messages, unread counts, dates, and order references shown in the screenshot are examples only and must not be hardcoded in production.

## 2. Implementation Principles

- Follow root `AGENTS.md`, root `DESIGN.md`, `mobile/AGENTS.md`, and `mobile/DESIGN.md`.
- Inspect existing Flutter architecture, Laravel messaging implementation, Docker configuration, and current Reverb/WebSocket settings before changing code.
- Reuse existing API clients, authentication, models, state management, theme, navigation shell, and error handling.
- Preserve existing code, backend contracts, authorization rules, uncommitted changes, and database data.
- Do not invent endpoints, database columns, migrations, event names, payloads, status values, or fake messages.
- Do not overwrite project-wide `DESIGN.md` files.
- Do not stage, commit, or push changes.
- Never run destructive database or Docker volume commands.

## 3. Screen Layout

### 3.1 App Bar
- AgroBenta green app bar.
- Back arrow if consistent with the current navigation entry point.
- Centered title: **Messages**.
- Compose/new-message icon on the right only if a supported conversation-starting workflow exists.
- Use existing icons; do not use emoji or arbitrary Unicode glyphs.
- Respect status-bar and safe-area insets.

### 3.2 Search
- Rounded search field with placeholder **Search conversations...**
- Search supported fields such as participant name or message preview only if available.
- Use local filtering for already-loaded small datasets or the existing server-side search contract where available.
- Debounce remote search if required by the existing architecture.
- Provide a clear-search affordance and an empty-results state.
- Do not expose conversations or private information the current user is not authorized to see.

### 3.3 Category Filters
Show selectable filters styled like the reference:
- **All**
- **Inquiries**
- **Transactions**
- **Notifications**

- Clearly distinguish the selected filter using the primary green style.
- Inspect the actual data model before deciding how each filter works.
- Notifications may be a separate feature from conversations. If so, use the existing notifications destination rather than pretending notifications are chat threads.
- Do not invent a transaction-message relationship or category field.
- If a category is unsupported, report the gap and do not populate it with fake data.

### 3.4 Conversation List
Each row should display, where available, real data:
- Participant avatar or neutral fallback.
- Participant/display name.
- Unread count or unread indicator.
- Last message preview.
- Last-message timestamp formatted appropriately.
- Read/delivered indicator only if supported by the backend.
- Subtle divider; pale green background for unread conversations if consistent with the theme.

Requirements:
- Use real conversations associated with the authenticated user.
- Do not hardcode names, images, messages, timestamps, unread counts, or order references.
- Never expose another user's conversations or private contact details.
- Handle missing avatars and empty previews safely.
- Truncate long previews without breaking layout.
- Sort by recent activity only if consistent with the backend contract.
- Do not assume a conversation exists merely because a listing or transaction exists.

### 3.5 Loading, Empty, and Error States
Implement:
- Initial loading indicator or skeleton using existing app patterns.
- Empty inbox state with concise guidance.
- Empty search/filter results state.
- Recoverable API/network error with retry.
- Expired authentication handling consistent with the app.
- WebSocket disconnected/reconnecting state if appropriate. Initial history should still load over HTTP.

## 4. Real-Time WebSocket Requirements

### 4.1 Inspect Before Integrating
Inspect the actual project for:
- Laravel Reverb installation and service configuration.
- `config/broadcasting.php`, `config/reverb.php`, relevant environment variables, and broadcasting configuration.
- Existing Laravel events, private channels, channel authorization, message controllers/models, and API routes.
- Docker Compose services, ports, hostnames, health checks, and environment wiring.
- Flutter WebSocket/Pusher-compatible client dependencies and connection abstractions.
- Existing authentication/token strategy for private-channel authorization.

Do not assume Reverb is enabled just because a port or environment variable exists. Verify the setup.

### 4.2 Connection Lifecycle
If a working approved WebSocket implementation exists:
- Reuse it.
- Connect only when required by the authenticated messaging feature.
- Subscribe only to the authenticated user's authorized private channels.
- Handle connect, disconnect, reconnect, authentication failure, and subscription failure.
- Avoid duplicate listeners/subscriptions.
- Unsubscribe and dispose resources correctly.
- Do not log tokens, message contents, or sensitive information.

If WebSocket infrastructure is missing or incomplete, identify the exact gap. Do not fake a connection or claim real-time support based on UI-only updates. Complete only safe work and report remaining setup.

### 4.3 Event Handling
Use only event names and payload structures verified from Laravel.

For a confirmed incoming-message event:
- Update the matching conversation preview and timestamp.
- Update unread state/count according to the actual read-state model.
- Move the conversation only according to established ordering behavior.
- Avoid duplicate messages when HTTP refresh and WebSocket events overlap.
- Do not create conversations from untrusted or unauthorized event data.
- Refresh through the API when event data is insufficient.

Implement sent/read/delivered events only if those events and states exist. Do not display delivery ticks that the backend cannot verify.

### 4.4 Initial Load and Reconnection
- Load conversation history/list through the actual HTTP API.
- Treat WebSocket as a live-update mechanism, not the only source of history.
- Reconcile after reconnecting so messages missed offline can be recovered from the server.
- Prevent duplicates when combining API results and live events.
- Never treat a successful WebSocket connection as proof that a message was saved.

### 4.5 Message Security
- Use the current authenticated identity.
- Enforce private-channel authorization in Laravel.
- Do not allow clients to subscribe to another user's channel by guessing an ID.
- Do not expose messages across users, roles, or unauthorized conversations.
- Validate message data server-side; do not trust client-supplied sender IDs or authorization decisions.

## 5. Conversation Navigation
- Tapping a row opens the existing conversation-detail screen, if implemented, using the real conversation ID.
- Mark a conversation read only through a supported endpoint or established server-side behavior.
- Do not mark messages read merely because a row was rendered.
- If the detail screen or endpoint is missing, report the gap rather than creating a fake destination.
- The compose icon should open a supported new-conversation flow. Do not create conversations from arbitrary IDs without server authorization.
- Preserve the current session and navigation shell.

## 6. Bottom Navigation
Use the existing bottom navigation order:
1. Home
2. Browse
3. Messages
4. Transactions
5. Profile

Highlight **Messages** while this screen is active. Reuse the existing shell and icons; do not add a second navigation bar or fake destinations.

## 7. Visual Design
- Green app bar and selected filter.
- White or near-white background.
- Rounded search field and filter chips.
- Circular participant avatars.
- Dark readable conversation titles.
- Muted grey message previews and timestamps.
- Green unread indicators and unread-count badges.
- Subtle row dividers and pale green unread-row background.
- Comfortable spacing and clear hierarchy.
- Responsive layout, safe-area support, and bottom-navigation insets.
- Reuse existing theme, typography, and icon package.

## 8. Backend/API Rules
Identify the actual endpoints and contracts for:
- Fetching the authenticated user's conversations.
- Fetching participants and last-message previews.
- Fetching and sending messages.
- Marking messages/conversations read, if supported.
- Authorizing private WebSocket channels.
- Broadcasting incoming messages, if configured.
- Searching/filtering conversations, if supported.

Do not create or rename routes, fields, events, or migrations without approval. If functionality is missing, report the exact backend gap and propose the smallest compatible change. Do not substitute Notifications or Transactions endpoints for messaging unless the architecture explicitly defines that relationship.

## 9. Testing and Verification
Before coding:
1. Read the project instruction/design files.
2. Inspect current mobile messaging code and backend routes/events.
3. Inspect Docker Reverb/WebSocket configuration and relevant environment variables without exposing secrets.
4. Check Git status and preserve uncommitted work.

Add or update tests for:
- Loading, empty, error, and retry states.
- Search and supported category filters.
- Correct conversation data rendering and unread indicators.
- Opening the correct conversation.
- WebSocket connection/reconnection where testable.
- Incoming event updates and duplicate-event prevention.
- Unauthorized channel/subscription rejection where backend tests apply.
- No cross-user conversation exposure.
- Proper disposal of stream subscriptions/listeners.

Run `dart format` on changed Dart files, `flutter analyze`, targeted and full Flutter tests when feasible, and relevant Laravel tests inside the configured PHP Docker container if backend files change. Check Docker service/configuration safely. Do not reset databases or volumes. Do not stage, commit, or push.

## 10. Acceptance Criteria
- Inbox visually matches the screenshot and existing AgroBenta design.
- All conversations and previews come from real authorized data.
- Search and category filters follow supported data.
- Tapping a conversation opens the correct existing conversation.
- Real-time updates use verified Laravel broadcast events and authorized channels.
- Initial history loads over HTTP and reconnect recovers missed messages.
- Duplicate messages and listeners are prevented.
- Unread/read indicators reflect actual backend state.
- Loading, empty, offline, error, and reconnect states are handled.
- No unsupported fields, endpoints, event names, or fake data are introduced.
- Existing code, database data, and unrelated changes remain intact.
- Tests and analysis results are reported honestly.

## 11. Completion Report
Report:
- Files created or modified.
- Existing messaging endpoints and data models used.
- Verified WebSocket provider, channel names, event names, and payload fields.
- Whether Reverb is configured and running in the current Docker setup.
- How private-channel authorization is enforced.
- Which inbox filters and read indicators are actually supported.
- Tests and commands run, with results.
- Remaining blockers and backend/configuration changes requiring approval.

Do not claim real-time messaging is complete unless a real authenticated WebSocket subscription receives server-broadcast events successfully.
