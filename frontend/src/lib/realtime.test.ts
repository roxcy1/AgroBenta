// @vitest-environment jsdom
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

type Handler = (data?: unknown) => void;

// Shared with the hoisted module mocks below.
const fake = vi.hoisted(() => ({
  options: undefined as Record<string, unknown> | undefined,
  socket: {} as Record<string, Handler>,
  channel: {} as Record<string, Handler>,
  constructed: 0,
}));

vi.mock('pusher-js', () => ({ default: class {} }));

vi.mock('laravel-echo', () => ({
  default: class {
    connector = {
      pusher: {
        connection: {
          bind: (event: string, cb: Handler) => {
            fake.socket[event] = cb;
          },
        },
      },
    };

    constructor(options: Record<string, unknown>) {
      fake.options = options;
      fake.constructed += 1;
    }

    private() {
      const chain = {
        subscribed: (cb: Handler) => {
          fake.channel.subscribed = cb;
          return chain;
        },
        error: (cb: Handler) => {
          fake.channel.error = cb;
          return chain;
        },
        listen: (event: string, cb: Handler) => {
          fake.channel[event] = cb;
          return chain;
        },
      };
      return chain;
    }

    disconnect() {}
  },
}));

import { connectAdminRealtime, describeSubscriptionError } from './realtime';

const TOKEN = '12|secret-admin-token';

describe('connectAdminRealtime', () => {
  beforeEach(() => {
    fake.options = undefined;
    fake.socket = {};
    fake.channel = {};
    fake.constructed = 0;
    localStorage.setItem('admin_token', TOKEN);
  });

  afterEach(() => {
    localStorage.clear();
    vi.restoreAllMocks();
  });

  it('does not connect without an admin token', () => {
    localStorage.clear();

    connectAdminRealtime(vi.fn());

    expect(fake.constructed).toBe(0);
  });

  it('re-fetches on a confirmed re-subscription, not on the bare socket connection', () => {
    vi.spyOn(console, 'info').mockImplementation(() => {});
    const onReconnected = vi.fn();

    connectAdminRealtime(vi.fn(), onReconnected);

    fake.socket.state_change?.({ previous: 'connecting', current: 'connected' });
    expect(onReconnected).not.toHaveBeenCalled();

    // The first subscription: the pages have just loaded, nothing to re-fetch.
    fake.channel.subscribed?.();
    expect(onReconnected).not.toHaveBeenCalled();

    // A reconnect re-subscribes: events may have been missed, so re-fetch.
    fake.socket.state_change?.({ previous: 'connected', current: 'unavailable' });
    fake.channel.subscribed?.();
    expect(onReconnected).toHaveBeenCalledTimes(1);

    fake.channel.subscribed?.();
    expect(onReconnected).toHaveBeenCalledTimes(2);
  });

  it('forwards a submitted user report to its handler', () => {
    const onUserReport = vi.fn();

    connectAdminRealtime(vi.fn(), vi.fn(), vi.fn(), onUserReport);
    fake.channel['.user-report.submitted']?.({ report_id: 9 });

    expect(onUserReport).toHaveBeenCalledWith({ report_id: 9 });
  });

  it('logs socket and subscription states as distinct messages', () => {
    const info = vi.spyOn(console, 'info').mockImplementation(() => {});

    connectAdminRealtime(vi.fn(), vi.fn());
    fake.socket.state_change?.({ previous: 'connecting', current: 'connected' });
    fake.channel.subscribed?.();

    expect(info.mock.calls.map((call) => call[0])).toEqual([
      '[realtime] socket connected',
      '[realtime] subscribed to private-admin',
    ]);
  });

  it('logs a refused subscription without the token or the response text', () => {
    const warn = vi.spyOn(console, 'warn').mockImplementation(() => {});
    const onReconnected = vi.fn();

    connectAdminRealtime(vi.fn(), onReconnected);
    fake.channel.error?.({
      type: 'AuthError',
      status: 403,
      error: `Bearer ${TOKEN} rejected`,
    });

    expect(warn).toHaveBeenCalledWith(
      '[realtime] private-admin subscription failed: AuthError (HTTP 403)',
    );
    expect(JSON.stringify(warn.mock.calls)).not.toContain(TOKEN);
    expect(onReconnected).not.toHaveBeenCalled();
  });

  it('sends the bearer token only in the channel-auth headers', () => {
    connectAdminRealtime(vi.fn());

    expect(fake.options?.auth).toEqual({ headers: { Authorization: `Bearer ${TOKEN}` } });
    expect(String(fake.options?.authEndpoint)).toMatch(/\/broadcasting\/auth$/);
  });
});

describe('describeSubscriptionError', () => {
  it('keeps only the type and status', () => {
    expect(describeSubscriptionError({ type: 'AuthError', status: 401, error: 'x' })).toBe(
      'AuthError (HTTP 401)',
    );
  });

  it('handles payloads without a status or of the wrong shape', () => {
    expect(describeSubscriptionError({ type: 'AuthError' })).toBe('AuthError');
    expect(describeSubscriptionError(null)).toBe('unknown error');
    expect(describeSubscriptionError('boom')).toBe('unknown error');
  });
});
