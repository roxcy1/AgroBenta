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

  // Echo re-subscribes the channel on its own, but the react-query caches do not
  // know about the socket. Fire on every (re)connection so the admin layout can
  // re-fetch anything missed while the socket was down.
  const connection = (
    echo.connector as unknown as {
      pusher?: { connection?: { bind: (event: string, cb: () => void) => void } };
    }
  ).pusher?.connection;
  connection?.bind('connected', () => onReconnected?.());

  echo
    .private('admin')
    .listen('.activity.recorded', (event: ActivityEvent) => onActivity(event));

  return () => {
    echo.disconnect();
  };
}
