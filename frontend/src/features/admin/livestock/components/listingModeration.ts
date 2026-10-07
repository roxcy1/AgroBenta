/**
 * The admin listing moderation rules, in one place.
 *
 * These are the client half of the documented lifecycle, and they are the
 * *narrowing* half: they say which actions an administrator is offered, never
 * which transitions are legal. The server decides that, inside a transaction,
 * and this module cannot widen it — a button that does not appear is a
 * convenience, and the 409 that `adminListingApi` surfaces is the boundary.
 *
 * Keeping the mapping here rather than in a component is what makes it testable
 * without a browser, and it means the table, the confirmation dialog and the
 * review panel cannot disagree about what a `pending` listing may do.
 */

export type ListingStatus = 'draft' | 'pending' | 'active' | 'sold' | 'inactive';

export type ModerationAction = 'approve' | 'reject' | 'deactivate';

export interface ModerationOption {
  action: ModerationAction;
  label: string;
  /** Which of the two existing button/confirm styles this action uses. */
  variant: 'approve' | 'reject';
  confirmTitle: string;
  confirmMessage: string;
  confirmLabel: string;
  /** The status the listing is expected to be in afterwards. */
  resultStatus: ListingStatus;
}

/**
 * Every status, in the order the contract's enum declares them.
 *
 * `status` is a plain string column with no enum behind it, so the list is
 * explicit rather than derived: an unknown value from a newer backend renders
 * as itself in the table and offers no actions, which is the safe direction to
 * fail in.
 */
export const LISTING_STATUSES: readonly ListingStatus[] = [
  'draft',
  'pending',
  'active',
  'sold',
  'inactive',
];

const PENDING_ACTIONS: readonly ModerationOption[] = [
  {
    action: 'approve',
    label: 'Approve',
    variant: 'approve',
    confirmTitle: 'Approve Listing',
    confirmMessage: 'Are you sure you want to approve this listing? It will become visible to buyers.',
    confirmLabel: 'Approve',
    resultStatus: 'active',
  },
  {
    action: 'reject',
    label: 'Reject',
    variant: 'reject',
    confirmTitle: 'Reject Listing',
    confirmMessage: 'Are you sure you want to reject this listing? It will be withdrawn and no longer visible to buyers.',
    confirmLabel: 'Reject',
    resultStatus: 'inactive',
  },
];

const ACTIVE_ACTIONS: readonly ModerationOption[] = [
  {
    action: 'deactivate',
    label: 'Deactivate',
    variant: 'reject',
    confirmTitle: 'Deactivate Listing',
    confirmMessage: 'Are you sure you want to deactivate this listing? It will be removed from the marketplace.',
    confirmLabel: 'Deactivate',
    resultStatus: 'inactive',
  },
];

/**
 * The actions available for a listing in `status`.
 *
 * `pending` yields approve and reject; `active` yields deactivate only, because
 * taking a live listing out of the marketplace is a different decision from
 * deciding whether to publish it. `draft` has never been reviewed, `sold` is
 * terminal, and `inactive` has already been through a decision — none of them
 * has anything to moderate, and none offers an action. In particular there is no
 * reactivation: the backend defines no path from `inactive` back to `active`,
 * so offering one would be a button that can only ever fail.
 */
export function moderationOptionsFor(status: string): readonly ModerationOption[] {
  switch (status) {
    case 'pending':
      return PENDING_ACTIONS;
    case 'active':
      return ACTIVE_ACTIONS;
    default:
      return [];
  }
}

/** Whether a listing in `status` is waiting on an administrator. */
export function isPendingReview(status: string): boolean {
  return status === 'pending';
}

/** Whether a listing in `status` can be opened for review at all. */
export function canReview(status: string): boolean {
  return moderationOptionsFor(status).length > 0;
}

/** The status a listing is expected to hold, for display. */
export function statusLabel(status: string): string {
  return status.charAt(0).toUpperCase() + status.slice(1);
}
