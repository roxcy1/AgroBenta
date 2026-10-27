import type { AxiosError } from 'axios';

/**
 * The inquiry vocabulary, in one place.
 *
 * An inquiry is the buyer-initiated contact record behind the marketplace
 * "Inquire" action. Its three states are the workflow bookmark the administrator
 * works with (`open` → `responded` → `closed`); the buyer never sees them. This
 * module is deliberately the *narrowing* half of that contract: it says how each
 * state reads and which badge colour stands in for it, never whether a
 * transition is legal. The server owns the transition rules, and a stale status
 * is answered there rather than guessed at here.
 *
 * Keeping the mapping out of the components is what makes it testable without a
 * browser (the test environment is node-only) and stops the table, the filter
 * and the detail dialog from disagreeing about what a status means.
 */

export type InquiryStatus = 'open' | 'responded' | 'closed';

export interface InquiryStatusOption {
  value: InquiryStatus;
  label: string;
}

/**
 * Every status, in the order the contract declares them, with its display
 * label. The list is explicit rather than derived from the API: an unknown
 * value from a newer backend renders as itself, which is safer than guessing.
 */
export const INQUIRY_STATUSES: readonly InquiryStatusOption[] = [
  { value: 'open', label: 'Open' },
  { value: 'responded', label: 'Responded' },
  { value: 'closed', label: 'Closed' },
];

export function statusLabel(status: string): string {
  const known = INQUIRY_STATUSES.find((entry) => entry.value === status);

  if (known) {
    return known.label;
  }

  return status.charAt(0).toUpperCase() + status.slice(1);
}

/**
 * The `lv-badge--*` modifier an inquiry status renders with.
 *
 * The global stylesheet only defines modifiers for the listing, verification and
 * transaction vocabularies; there is no `open`/`responded`/`closed` rule. Rather
 * than add CSS, each state reuses the closest existing modifier so the badge
 * still reads as intended: `open` is an outstanding item (amber, `pending`),
 * `responded` is in good standing (green, `active`), and `closed` is finished
 * (grey, `inactive`).
 */
const BADGE_MODIFIER: Record<string, string> = {
  open: 'pending',
  responded: 'active',
  closed: 'inactive',
};

export function statusBadgeModifier(status: string): string {
  return BADGE_MODIFIER[status] ?? 'inactive';
}

export function statusBadgeClass(status: string): string {
  return `lv-badge lv-badge--${statusBadgeModifier(status)}`;
}

/** The three states offered by the status filter, plus an "all" sentinel. */
export const INQUIRY_STATUS_FILTER_OPTIONS: ReadonlyArray<{ value: string; label: string }> = [
  { value: '', label: 'All Statuses' },
  ...INQUIRY_STATUSES.map((entry) => ({ value: entry.value as string, label: entry.label })),
];

export function transactionMethodLabel(value: string | null | undefined): string {
  switch (value) {
    case 'direct_deal':
      return 'Direct Deal';
    case 'arrange_delivery':
      return 'Arrange Delivery';
    case null:
    case undefined:
    case '':
      return '\u2014';
    default:
      return value;
  }
}

export function contactMethodLabel(value: string | null | undefined): string {
  if (value === 'in_app_message') {
    return 'In-App Message';
  }

  if (value === null || value === undefined || value === '') {
    return '\u2014';
  }

  return value;
}

/**
 * Renders the optional purchase-interest flag. `null` means the buyer did not
 * state an intention, which is shown as a dash rather than as "No" — the two
 * are not the same answer.
 */
export function interestLabel(value: boolean | null | undefined): string {
  if (value === null || value === undefined) {
    return '\u2014';
  }

  return value ? 'Yes' : 'No';
}

/**
 * A status-change or delete failure the administrator can act on.
 *
 * Mirrors the verification feature's error contract: a 409 never applies here
 * because the status transition is unconstrained, but a missing record (404) is
 * the interesting one — another administrator may have deleted it. The mutation
 * hooks invalidate the inquiry queries either way, so the list behind the dialog
 * is already being re-read.
 */
export function inquiryErrorMessage(error: unknown): string {
  const status = (error as AxiosError<{ message?: string }>)?.response?.status;

  switch (status) {
    case 403:
      return 'You do not have permission to manage inquiries.';
    case 404:
      return 'This inquiry no longer exists. It may have been deleted.';
    case 422:
      return 'The request was rejected. Please check the selected status and try again.';
    case 500:
      return 'The server could not complete the request. Please try again.';
    default:
      return 'Something went wrong. Please try again.';
  }
}
