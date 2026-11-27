import type { QueryClient } from '@tanstack/react-query';
import type { ActivityEvent } from '../../../lib/realtime';
import { ADMIN_USER_REPORTS_QUERY_KEY } from '../users/api/useUserReports';

type QueryKey = readonly unknown[];

/** The analytics behind the Reports page (users, listings, sales, prices). */
const REPORT_ANALYTICS: QueryKey = ['admin', 'reports'];

/**
 * Which admin lists an audited action changes, by `ActivityAction` prefix.
 *
 * The prefixes are matched with their trailing underscore so that, for
 * example, `user_logged_in` never matches `user_report_` and `admin_logged_in`
 * never matches `admin_user_`. Login actions change only the activity feed and
 * dashboard, which every action refreshes.
 */
const DOMAIN_KEYS: ReadonlyArray<readonly [prefix: string, keys: QueryKey[]]> = [
  ['listing_', [['admin', 'listings'], REPORT_ANALYTICS]],
  [
    'seller_verification_',
    [['admin', 'seller-verifications'], ['admin', 'users'], REPORT_ANALYTICS],
  ],
  ['inquiry_', [['admin', 'transactions']]],
  ['offer_', [['admin', 'transactions'], REPORT_ANALYTICS]],
  ['transaction_', [['admin', 'transactions'], REPORT_ANALYTICS]],
  ['settings_', [['admin', 'settings']]],
  // Account edits, deactivation and reactivation: the Users list and the user
  // figures in the Reports analytics.
  ['admin_user_', [['admin', 'users'], REPORT_ANALYTICS]],
  // A dismissed or actioned report leaves the pending queue; an actioned one
  // also deactivates the reported account.
  ['user_report_', [ADMIN_USER_REPORTS_QUERY_KEY, ['admin', 'users']]],
];

/**
 * Invalidate the admin react-query caches affected by an audited action.
 *
 * Every audited action refreshes the activity feed and the aggregate
 * dashboard; the domain-specific lists are refreshed only when the action's
 * prefix matches, so one write does not refetch every admin screen.
 * Invalidating a query no screen is showing only marks it stale; it costs a
 * request only when that screen is next shown.
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

  const match = DOMAIN_KEYS.find(([prefix]) => action.startsWith(prefix));
  for (const queryKey of match?.[1] ?? []) {
    void queryClient.invalidateQueries({ queryKey });
  }
}

/**
 * A user submitted a report. Submission is not an audited action (no
 * `activity.recorded`), so it has its own event: refresh the pending-report
 * queue and the Users list, whose rows carry each account's report count.
 */
export function invalidateForUserReport(queryClient: QueryClient): void {
  void queryClient.invalidateQueries({ queryKey: ADMIN_USER_REPORTS_QUERY_KEY });
  void queryClient.invalidateQueries({ queryKey: ['admin', 'users'] });
}
