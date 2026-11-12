import { describe, expect, it, vi } from 'vitest';
import type { QueryClient } from '@tanstack/react-query';
import type { ActivityEvent } from '../../../lib/realtime';
import { invalidateForActivity } from './adminRealtimeInvalidation';

function makeClient() {
  const invalidateQueries = vi.fn();
  return {
    client: { invalidateQueries } as unknown as QueryClient,
    invalidateQueries,
  };
}

function event(action: string): ActivityEvent {
  return {
    id: 1,
    user_id: 1,
    action,
    description: null,
    created_at: '2026-01-01T00:00:00.000000Z',
  };
}

function keys(invalidateQueries: ReturnType<typeof vi.fn>): unknown[][] {
  return invalidateQueries.mock.calls.map(
    (call) => (call[0] as { queryKey: unknown[] }).queryKey,
  );
}

describe('invalidateForActivity', () => {
  it('always refreshes the activity feed and dashboard', () => {
    const { client, invalidateQueries } = makeClient();

    invalidateForActivity(client, event('admin_logged_in'));

    expect(keys(invalidateQueries)).toEqual([
      ['admin', 'activities'],
      ['admin', 'dashboard'],
    ]);
  });

  it('refreshes listings for a listing action', () => {
    const { client, invalidateQueries } = makeClient();

    invalidateForActivity(client, event('listing_approved'));

    expect(keys(invalidateQueries)).toContainEqual(['admin', 'listings']);
  });

  it('refreshes the verification queue and users for a verification action', () => {
    const { client, invalidateQueries } = makeClient();

    invalidateForActivity(client, event('seller_verification_approved'));

    const called = keys(invalidateQueries);
    expect(called).toContainEqual(['admin', 'seller-verifications']);
    expect(called).toContainEqual(['admin', 'users']);
  });

  it.each(['inquiry_created', 'offer_accepted', 'transaction_cancelled'])(
    'refreshes transactions for %s',
    (action) => {
      const { client, invalidateQueries } = makeClient();

      invalidateForActivity(client, event(action));

      expect(keys(invalidateQueries)).toContainEqual(['admin', 'transactions']);
    },
  );

  it('refreshes settings for a settings action', () => {
    const { client, invalidateQueries } = makeClient();

    invalidateForActivity(client, event('settings_updated'));

    expect(keys(invalidateQueries)).toContainEqual(['admin', 'settings']);
  });

  it('does not refresh a domain list for an unrelated action', () => {
    const { client, invalidateQueries } = makeClient();

    invalidateForActivity(client, event('admin_logged_in'));

    const called = keys(invalidateQueries);
    expect(called).not.toContainEqual(['admin', 'listings']);
    expect(called).not.toContainEqual(['admin', 'transactions']);
    expect(called).not.toContainEqual(['admin', 'settings']);
  });
});
