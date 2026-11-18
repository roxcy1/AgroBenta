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

export type ModerationAction = 'approve' | 'reject' | 'deactivate' | 'reactivate';

export interface ReactivationInventory {
  quantity: number;
  total_quantity: number | null;
  reserved_quantity: number | null;
  platform_sold_quantity: number | null;
  externally_sold_quantity: number | null;
  available_quantity: number | null;
  inventory_reconciliation_required: boolean;
}

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

const REACTIVATE_ACTION: ModerationOption = {
  action: 'reactivate',
  label: 'Reactivate',
  variant: 'approve',
  confirmTitle: 'Reactivate Listing',
  confirmMessage: 'Reactivate this listing? It will become active and visible in the Marketplace again.',
  confirmLabel: 'Reactivate',
  resultStatus: 'active',
};

/**
 * The actions available for a listing in `status`.
 *
 * `pending` yields approve and reject; `active` yields deactivate. An inactive
 * listing may offer reactivation only when the response contains reconciled,
 * internally consistent, positive inventory. Source of deactivation and seller
 * eligibility are not in this API projection, so the backend remains authoritative
 * for those checks and may refuse an otherwise inventory-eligible attempt.
 */
export function moderationOptionsFor(
  status: string,
  inventory?: ReactivationInventory,
): readonly ModerationOption[] {
  switch (status) {
    case 'pending':
      return PENDING_ACTIONS;
    case 'active':
      return ACTIVE_ACTIONS;
    case 'inactive':
      return canPreliminarilyReactivate(inventory) ? [REACTIVATE_ACTION] : [];
    default:
      return [];
  }
}

/** Preliminary inventory screening only; the backend performs authoritative checks. */
export function canPreliminarilyReactivate(
  inventory: ReactivationInventory | undefined,
): boolean {
  if (
    inventory === undefined ||
    inventory.inventory_reconciliation_required ||
    inventory.total_quantity === null ||
    inventory.reserved_quantity === null ||
    inventory.platform_sold_quantity === null ||
    inventory.externally_sold_quantity === null ||
    inventory.available_quantity === null ||
    inventory.available_quantity < 1
  ) {
    return false;
  }

  const calculatedAvailable =
    inventory.total_quantity -
    inventory.reserved_quantity -
    inventory.platform_sold_quantity -
    inventory.externally_sold_quantity;

  return calculatedAvailable === inventory.quantity &&
    inventory.available_quantity === inventory.quantity;
}

/** Whether a listing in `status` is waiting on an administrator. */
export function isPendingReview(status: string): boolean {
  return status === 'pending';
}

/** Whether a listing in `status` can be opened for review at all. */
export function canReview(status: string): boolean {
  return moderationOptionsFor(status).length > 0;
}

/** The name shown for a status. One source for every page: `src/lib/status.ts`. */
export { statusLabel } from '../../../../lib/status';
