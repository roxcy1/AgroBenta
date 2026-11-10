import type { QueryClient } from '@tanstack/react-query';
import type { ActivityEvent } from '../../../lib/realtime';

/**
 * Invalidate the admin react-query caches affected by an audited action.
 *
 * Every audited action refreshes the activity feed and the aggregate
 * dashboard; the domain-specific list is refreshed only when its action prefix
 * matches, so one write does not refetch every admin screen.
 *
 * Kept free of the Echo/pusher imports so it can be unit-tested in a plain
 * Node environment (the live client lives in `useAdminRealtime`).
 */
export function invalidateForActivity(
  queryClient: QueryClient,
  event: ActivityEvent,
): void {
  const action = typeof event.action === 'string' ? event.action : '';

  void queryClient.invalidateQueries({ queryKey: ['admin', 'activities'] });
  void queryClient.invalidateQueries({ queryKey: ['admin', 'dashboard'] });

  if (action.startsWith('listing')) {
    void queryClient.invalidateQueries({ queryKey: ['admin', 'listings'] });
  } else if (action.startsWith('seller_verification')) {
    void queryClient.invalidateQueries({ queryKey: ['admin', 'seller-verifications'] });
    void queryClient.invalidateQueries({ queryKey: ['admin', 'users'] });
  } else if (
    action.startsWith('inquiry') ||
    action.startsWith('offer') ||
    action.startsWith('transaction')
  ) {
    void queryClient.invalidateQueries({ queryKey: ['admin', 'transactions'] });
  } else if (action.startsWith('settings')) {
    void queryClient.invalidateQueries({ queryKey: ['admin', 'settings'] });
  }
}
