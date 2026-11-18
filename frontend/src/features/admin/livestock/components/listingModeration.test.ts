import { describe, expect, it } from 'vitest';
import {
  LISTING_STATUSES,
  canReview,
  isPendingReview,
  moderationOptionsFor,
  statusLabel,
} from './listingModeration';

describe('moderationOptionsFor', () => {
  it('offers approve and reject to a listing awaiting review', () => {
    expect(moderationOptionsFor('pending').map((o) => o.action)).toEqual([
      'approve',
      'reject',
    ]);
  });

  it('offers only deactivate to a live listing', () => {
    // Taking a published listing out of the marketplace is a different decision
    // from deciding whether to publish it, so a live listing is not offered a
    // re-review.
    expect(moderationOptionsFor('active').map((o) => o.action)).toEqual(['deactivate']);
  });

  it('offers nothing to an inactive listing when inventory data is not available', () => {
    // Without inventory data the preliminary check cannot establish that a
    // restoration attempt is worth offering.
    expect(moderationOptionsFor('inactive')).toEqual([]);
  });

  it('offers Reactivate for an inactive listing with consistent positive inventory', () => {
    expect(moderationOptionsFor('inactive', eligibleInventory).map((option) => option.action))
      .toEqual(['reactivate']);
  });

  it.each([
    ['reconciliation required', { ...eligibleInventory, inventory_reconciliation_required: true }],
    ['no available stock', { ...eligibleInventory, quantity: 0, available_quantity: 0 }],
    ['unknown inventory totals', { ...eligibleInventory, total_quantity: null }],
    ['inconsistent inventory totals', { ...eligibleInventory, total_quantity: 5 }],
  ])('hides Reactivate when inventory has a known blocker: %s', (_case, inventory) => {
    expect(moderationOptionsFor('inactive', inventory)).toEqual([]);
  });

  it('offers nothing to a draft, which has never been reviewed', () => {
    expect(moderationOptionsFor('draft')).toEqual([]);
  });

  it('offers nothing to a sold listing, which is terminal', () => {
    expect(moderationOptionsFor('sold')).toEqual([]);
  });

  it('offers nothing to a status it does not recognise', () => {
    // `status` is a string column with no enum behind it, so a value from a
    // newer backend must not crash the table. Failing towards no actions is the
    // only safe direction: the server still refuses anything invalid.
    expect(moderationOptionsFor('archived')).toEqual([]);
    expect(moderationOptionsFor('')).toEqual([]);
  });

  it('never offers an action that the server has no endpoint for', () => {
    // Every client action must correspond to one of the backend's named routes.
    const offered = LISTING_STATUSES.flatMap((status) =>
      moderationOptionsFor(status, eligibleInventory).map((o) => o.action),
    );

    expect(new Set(offered)).toEqual(new Set(['approve', 'reject', 'deactivate', 'reactivate']));
  });

  it('never offers the same action twice for one listing', () => {
    for (const status of LISTING_STATUSES) {
      const actions = moderationOptionsFor(status).map((o) => o.action);
      expect(new Set(actions).size).toBe(actions.length);
    }
  });
});

describe('the destinations each action expects', () => {
  it('matches the documented lifecycle', () => {
    const result = (status: string, action: string) =>
      moderationOptionsFor(status).find((o) => o.action === action)?.resultStatus;

    expect(result('pending', 'approve')).toBe('active');
    expect(result('pending', 'reject')).toBe('inactive');
    expect(result('active', 'deactivate')).toBe('inactive');
  });

  it('reactivates an inventory-eligible inactive listing to active', () => {
    const option = moderationOptionsFor('inactive', eligibleInventory)[0];

    expect(option.resultStatus).toBe('active');
    expect(option.label).toBe('Reactivate');
    expect(option.confirmMessage).toContain('visible in the Marketplace again');
  });

  it('gives every action copy that names its own confirmation', () => {
    // The confirmation text is the only place a moderator is told the decision
    // is final, so an action without it would ship a silent irreversible click.
    for (const status of LISTING_STATUSES) {
      for (const option of moderationOptionsFor(status)) {
        expect(option.confirmTitle.length).toBeGreaterThan(0);
        expect(option.confirmMessage).toMatch(/listing/i);
        expect(option.confirmLabel.length).toBeGreaterThan(0);
      }
    }
  });
});

const eligibleInventory = {
  quantity: 4,
  total_quantity: 6,
  reserved_quantity: 1,
  platform_sold_quantity: 1,
  externally_sold_quantity: 0,
  available_quantity: 4,
  inventory_reconciliation_required: false,
};

describe('isPendingReview', () => {
  it('is true for exactly one status', () => {
    const pending = LISTING_STATUSES.filter(isPendingReview);

    expect(pending).toEqual(['pending']);
  });
});

describe('canReview', () => {
  it('agrees with the actions on offer', () => {
    for (const status of LISTING_STATUSES) {
      expect(canReview(status)).toBe(moderationOptionsFor(status).length > 0);
    }
  });

  it('is false for an unrecognised status', () => {
    expect(canReview('archived')).toBe(false);
  });
});

describe('statusLabel', () => {
  it('capitalises the status for display', () => {
    expect(statusLabel('pending')).toBe('Pending');
    expect(statusLabel('inactive')).toBe('Inactive');
  });

  it('renders an unknown status as itself rather than blank', () => {
    expect(statusLabel('archived')).toBe('Archived');
  });
});
