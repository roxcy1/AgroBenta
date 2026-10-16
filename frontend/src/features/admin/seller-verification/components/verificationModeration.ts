import type { AxiosError } from 'axios';

/**
 * The seller-verification review rules, in one place.
 *
 * The four states are fixed by the approved functional documentation (§3.1):
 * `submitted` and `pending_review` are *open* — a review is in flight — while
 * `approved` and `rejected` are terminal. This module is the client half of
 * that contract and is deliberately the *narrowing* half: it only says which
 * tabs exist and which states are open, never which transitions are legal. The
 * server decides that inside a transaction, and the 409 it answers for a stale
 * or already-reviewed record is the real boundary.
 *
 * Keeping the mapping here rather than in a component is what makes it testable
 * without a browser (the test environment is node-only), and it means the tabs,
 * the table and the review dialog cannot disagree about what a status means.
 */

export type VerificationStatus = 'submitted' | 'pending_review' | 'approved' | 'rejected';

export interface VerificationTab {
  value: VerificationStatus;
  label: string;
}

/**
 * Every status, in the order the contract declares them, with its display
 * label. The list is explicit rather than derived from the API: an unknown
 * value from a newer backend renders as itself and offers no actions, which is
 * the safe direction to fail in.
 */
export const VERIFICATION_TABS: readonly VerificationTab[] = [
  { value: 'submitted', label: 'Submitted' },
  { value: 'pending_review', label: 'Pending Review' },
  { value: 'approved', label: 'Approved' },
  { value: 'rejected', label: 'Rejected' },
];

/**
 * Resolve a `?status=` deep-link value to the tab the page should open on.
 *
 * Unknown or absent values fall back to the default `submitted` tab, so a
 * stale or hand-edited link can never put the page in a state it cannot render.
 * Kept here, beside the tab list, so the URL contract and the tabs cannot drift.
 */
export function resolveStatusTab(value: string | null | undefined): VerificationStatus {
  const known = VERIFICATION_TABS.find((tab) => tab.value === value);

  return known ? known.value : 'submitted';
}

/**
 * The two in-flight states. A verification in either may be reviewed; anything
 * else is already decided and the server answers 409 rather than re-review it.
 */
export const OPEN_VERIFICATION_STATUSES: readonly VerificationStatus[] = [
  'submitted',
  'pending_review',
];

export function isOpenStatus(status: string): boolean {
  return (OPEN_VERIFICATION_STATUSES as readonly string[]).includes(status);
}

/**
 * The two review actions, and the confirmation each one shows.
 *
 * Mirrors the livestock `moderationOptionsFor()` shape, and is the *narrowing*
 * half of the contract in the same way: it only decides which actions an open
 * record offers. An approved or rejected record is terminal and offers none —
 * the server answers 409 rather than let it be re-reviewed, so offering a
 * button there would only ever fail.
 */
export type VerificationAction = 'approve' | 'reject';

export interface VerificationActionConfig {
  action: VerificationAction;
  label: string;
  variant: 'approve' | 'reject';
  confirmTitle: string;
  confirmMessage: string;
  confirmLabel: string;
  /** Rejection must carry a note; approval may. Enforced server-side. */
  noteRequired: boolean;
}

const ACTION_CONFIGS: Record<VerificationAction, VerificationActionConfig> = {
  approve: {
    action: 'approve',
    label: 'Approve',
    variant: 'approve',
    confirmTitle: 'Approve Verification',
    confirmMessage:
      'This will approve the verification and grant the applicant seller capability, allowing them to list and sell on the platform.',
    confirmLabel: 'Approve',
    noteRequired: false,
  },
  reject: {
    action: 'reject',
    label: 'Reject',
    variant: 'reject',
    confirmTitle: 'Reject Verification',
    confirmMessage:
      'This will reject the verification and revoke seller capability. If the applicant is already an approved seller, they will be returned to a buyer and can no longer sell or list.',
    confirmLabel: 'Reject',
    noteRequired: true,
  },
};

/**
 * The actions available for a verification in `status`.
 *
 * `submitted` and `pending_review` yield approve and reject; a decided record
 * yields nothing, because both outcomes are terminal.
 */
export function verificationActionsFor(status: string): readonly VerificationActionConfig[] {
  return isOpenStatus(status) ? [ACTION_CONFIGS.approve, ACTION_CONFIGS.reject] : [];
}


export function statusLabel(status: string): string {
  const known = VERIFICATION_TABS.find((tab) => tab.value === status);

  if (known) {
    return known.label;
  }

  return status.charAt(0).toUpperCase() + status.slice(1);
}

/**
 * How often the verification views re-read themselves while nothing is being
 * clicked. A decision made in another administrator's session shows up without
 * a manual refresh, which matters because the review endpoints are
 * first-write-wins.
 */
export const VERIFICATION_POLL_INTERVAL_MS = 30_000;

/**
 * The `refetchInterval` passed to React Query for the verification queries.
 *
 * Returning `false` disables the interval, so the poll stops while the tab is
 * hidden and no request is fired against a page nobody is looking at. The
 * `typeof document` guard keeps the function safe in the node test environment,
 * where there is no `document` to read.
 */
export function verificationPollingInterval(): number | false {
  if (typeof document === 'undefined' || document.visibilityState !== 'visible') {
    return false;
  }

  return VERIFICATION_POLL_INTERVAL_MS;
}

/**
 * A review failure the administrator can act on.
 *
 * Mirrors the livestock `moderationErrorMessage()` contract. A 409 is the
 * interesting one and gets its own message: the record was either already
 * decided or is no longer the applicant's most recent submission, which almost
 * always means another administrator acted first. The mutation hooks invalidate
 * the verification queries either way, so the list behind the dialog is already
 * being re-read — the message says so rather than leaving the administrator to
 * wonder whether to retry.
 */
export function verificationErrorMessage(error: unknown): string {
  const status = (error as AxiosError<{ message?: string }>)?.response?.status;

  switch (status) {
    case 403:
      return 'You do not have permission to review seller verifications.';
    case 404:
      return 'This verification request no longer exists.';
    case 409:
      return 'This request has already been reviewed or is no longer the applicant\u2019s most recent submission. The list has been refreshed with its current state.';
    case 422:
      return 'The action was rejected as invalid. Check the details and try again.';
    case 500:
      return 'The server could not complete the action. Please try again.';
    default:
      return 'The action could not be completed. Check your connection and try again.';
  }
}
