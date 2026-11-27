import Echo from 'laravel-echo';
import Pusher from 'pusher-js';

declare global {
  interface Window {
    Pusher: typeof Pusher;
  }
}

const API_BASE_URL = import.meta.env.VITE_API_URL ?? 'http://localhost:8001/api';
// Strip the `/api` mount to reach the origin that serves `/broadcasting/auth`.
const API_ORIGIN = API_BASE_URL.replace(/\/api\/?$/, '');

const REVERB_HOST = import.meta.env.VITE_REVERB_HOST ?? 'localhost';
const REVERB_PORT = Number(import.meta.env.VITE_REVERB_PORT ?? '8083');
const REVERB_SCHEME = import.meta.env.VITE_REVERB_SCHEME ?? 'http';
// The Reverb application key is public (it is in the WebSocket path); the
// matching secret never leaves the server. Override per environment.
const REVERB_APP_KEY =
  import.meta.env.VITE_REVERB_APP_KEY ?? 'de12af69703d6055c123e7a63469dee7';

/** The payload of the backend's `activity.recorded` event. */
export interface ActivityEvent {
  id: number;
  user_id: number | null;
  action: string;
  description: string | null;
  created_at: string | null;
}

export interface ListingInventoryEvent {
  listing_id: number;
}

/** The payload of the backend's `user-report.submitted` event (id only). */
export interface UserReportEvent {
  report_id: number;
}

const LOGGED_SOCKET_STATES = new Set(['connected', 'unavailable', 'failed', 'disconnected']);

/**
 * A loggable description of a failed channel subscription (pusher-js passes
 * `{ type, error, status }`). Only the type and HTTP status are kept: the
 * error text can echo the server response, and the token is never included.
 */
export function describeSubscriptionError(error: unknown): string {
  if (error === null || typeof error !== 'object') {
    return 'unknown error';
  }
  const { type, status } = error as { type?: unknown; status?: unknown };
  const label = typeof type === 'string' ? type : 'error';
  return typeof status === 'number' ? `${label} (HTTP ${status})` : label;
}

/**
 * Connect the Admin Web's WebSocket client and subscribe to the shared admin
 * channel. Returns a cleanup function.
 *
 * Best-effort: if Echo cannot connect, the admin pages keep working with
 * react-query's normal refetch behaviour. The bearer token is read from
 * `localStorage` (the Admin Web's token store) and sent only to the
 * `/broadcasting/auth` endpoint — it is never logged.
 */
export function connectAdminRealtime(
  onActivity: (event: ActivityEvent) => void,
  onReconnected?: () => void,
  onListingInventoryUpdated?: (event: ListingInventoryEvent) => void,
  onUserReportSubmitted?: (event: UserReportEvent) => void,
): () => void {
  const token = localStorage.getItem('admin_token');
  if (!token) {
    return () => {};
  }

  window.Pusher = Pusher;

  const echo = new Echo({
    broadcaster: 'reverb',
    key: REVERB_APP_KEY,
    wsHost: REVERB_HOST,
    wsPort: REVERB_PORT,
    wssPort: REVERB_PORT,
    forceTLS: REVERB_SCHEME === 'https',
    enabledTransports: ['ws', 'wss'],
    authEndpoint: `${API_ORIGIN}/broadcasting/auth`,
    auth: {
      headers: {
        Authorization: `Bearer ${token}`,
      },
    },
  });

  // Socket state is logged separately from the channel subscription: an open
  // socket whose channel authorization was refused delivers nothing.
  const connection = (
    echo.connector as unknown as {
      pusher?: {
        connection?: { bind: (event: string, cb: (data?: unknown) => void) => void };
      };
    }
  ).pusher?.connection;
  connection?.bind('state_change', (change) => {
    const current = (change as { current?: unknown } | undefined)?.current;
    if (typeof current === 'string' && LOGGED_SOCKET_STATES.has(current)) {
      console.info(`[realtime] socket ${current}`);
    }
  });

  let subscribedBefore = false;

  echo
    .private('admin')
    // Echo re-subscribes the channel on its own after a reconnect, but the
    // react-query caches do not know about the socket. Fire on every confirmed
    // *re*-subscription — not on the bare socket connection — so the re-fetch
    // happens once events are actually live again. The first subscription is
    // skipped: the pages on screen have just loaded, so a refetch would only
    // repeat every request.
    .subscribed(() => {
      console.info('[realtime] subscribed to private-admin');
      if (subscribedBefore) {
        onReconnected?.();
      }
      subscribedBefore = true;
    })
    .error((error: unknown) => {
      console.warn(
        `[realtime] private-admin subscription failed: ${describeSubscriptionError(error)}`,
      );
    })
    .listen('.activity.recorded', (event: ActivityEvent) => onActivity(event))
    .listen(
      '.listing.inventory.updated',
      (event: ListingInventoryEvent) => onListingInventoryUpdated?.(event),
    )
    .listen('.user-report.submitted', (event: UserReportEvent) =>
      onUserReportSubmitted?.(event),
    );

  return () => {
    echo.disconnect();
  };
}
