import { describe, expect, it } from 'vitest';
import {
  OPEN_VERIFICATION_STATUSES,
  VERIFICATION_POLL_INTERVAL_MS,
  VERIFICATION_TABS,
  isOpenStatus,
  resolveStatusTab,
  statusLabel,
  verificationActionsFor,
  verificationErrorMessage,
  verificationPollingInterval,
} from './verificationModeration';

describe('VERIFICATION_TABS', () => {
  it('covers exactly the four documented states, in order', () => {
    expect(VERIFICATION_TABS.map((tab) => tab.value)).toEqual([
      'submitted',
      'pending_review',
      'approved',
      'rejected',
    ]);
  });

  it('gives every tab a non-empty label', () => {
    for (const tab of VERIFICATION_TABS) {
      expect(tab.label.length).toBeGreaterThan(0);
    }
  });

  it('has no duplicate tab', () => {
    const values = VERIFICATION_TABS.map((tab) => tab.value);
    expect(new Set(values).size).toBe(values.length);
  });
});

describe('resolveStatusTab', () => {
  it('resolves every known tab value to itself', () => {
    for (const tab of VERIFICATION_TABS) {
      expect(resolveStatusTab(tab.value)).toBe(tab.value);
    }
  });

  it('resolves the deep-link target used by the dashboard card', () => {
    expect(resolveStatusTab('pending_review')).toBe('pending_review');
  });

  it('falls back to the default tab for an unknown, empty, or absent value', () => {
    expect(resolveStatusTab('archived')).toBe('submitted');
    expect(resolveStatusTab('')).toBe('submitted');
    expect(resolveStatusTab(null)).toBe('submitted');
    expect(resolveStatusTab(undefined)).toBe('submitted');
  });
});

describe('OPEN_VERIFICATION_STATUSES', () => {
  it('is exactly the two in-flight states', () => {
    expect([...OPEN_VERIFICATION_STATUSES]).toEqual(['submitted', 'pending_review']);
  });

  it('shares the tab vocabulary, so no open state can be unreachable', () => {
    const tabValues = VERIFICATION_TABS.map((tab) => tab.value);
    for (const status of OPEN_VERIFICATION_STATUSES) {
      expect(tabValues).toContain(status);
    }
  });
});

describe('isOpenStatus', () => {
  it('is true only for the open states', () => {
    expect(isOpenStatus('submitted')).toBe(true);
    expect(isOpenStatus('pending_review')).toBe(true);
  });

  it('is false for a decided state or an unknown value', () => {
    expect(isOpenStatus('approved')).toBe(false);
    expect(isOpenStatus('rejected')).toBe(false);
    expect(isOpenStatus('archived')).toBe(false);
  });
});

describe('statusLabel', () => {
  it('uses the human label for the multi-word state', () => {
    expect(statusLabel('pending_review')).toBe('Pending Review');
  });

  it('capitalises the single-word states', () => {
    expect(statusLabel('submitted')).toBe('Submitted');
    expect(statusLabel('approved')).toBe('Approved');
    expect(statusLabel('rejected')).toBe('Rejected');
  });

  it('renders an unknown status as itself rather than blank', () => {
    expect(statusLabel('archived')).toBe('Archived');
  });
});

describe('verificationActionsFor', () => {
  it('offers approve and reject for an open record', () => {
    expect(verificationActionsFor('submitted').map((a) => a.action)).toEqual([
      'approve',
      'reject',
    ]);
    expect(verificationActionsFor('pending_review').map((a) => a.action)).toEqual([
      'approve',
      'reject',
    ]);
  });

  it('offers nothing for a decided record or an unknown value', () => {
    expect(verificationActionsFor('approved')).toEqual([]);
    expect(verificationActionsFor('rejected')).toEqual([]);
    expect(verificationActionsFor('archived')).toEqual([]);
  });

  it('marks the note as required only for rejection', () => {
    const [approve, reject] = verificationActionsFor('submitted');

    expect(approve.noteRequired).toBe(false);
    expect(reject.noteRequired).toBe(true);
  });

  it('matches each action variant to the action', () => {
    const [approve, reject] = verificationActionsFor('submitted');

    expect(approve.variant).toBe('approve');
    expect(reject.variant).toBe('reject');
  });
});

describe('review safeguards copy', () => {
  it('states that approval grants selling capability', () => {
    const [approve] = verificationActionsFor('submitted');

    expect(approve.confirmMessage).toMatch(/seller capability/i);
    expect(approve.confirmMessage).toMatch(/sell/i);
  });

  it('warns that rejection revokes capability even for an already-approved seller', () => {
    const [, reject] = verificationActionsFor('submitted');

    expect(reject.confirmMessage).toMatch(/revoke/i);
    expect(reject.confirmMessage).toMatch(/already an approved seller/i);
  });
});

describe('verificationErrorMessage', () => {

  const axiosError = (status: number) => ({ response: { status } });

  it('explains a 409 as a stale or already-reviewed record and names the refresh', () => {
    const message = verificationErrorMessage(axiosError(409));

    expect(message).toMatch(/already been reviewed|most recent/i);
    expect(message).toMatch(/refresh/i);
  });

  it('maps 403 to a permission message', () => {
    expect(verificationErrorMessage(axiosError(403))).toMatch(/permission/i);
  });

  it('maps 404 to a missing-record message', () => {
    expect(verificationErrorMessage(axiosError(404))).toMatch(/no longer exists/i);
  });

  it('maps 422 to an invalid-action message', () => {
    expect(verificationErrorMessage(axiosError(422))).toMatch(/invalid/i);
  });

  it('maps 500 to a server message', () => {
    expect(verificationErrorMessage(axiosError(500))).toMatch(/server/i);
  });

  it('falls back to a connection message for an unknown status', () => {
    expect(verificationErrorMessage(axiosError(418))).toMatch(/could not be completed/i);
  });

  it('falls back for a missing response or a non-axios error', () => {
    expect(verificationErrorMessage(new Error('boom'))).toMatch(/could not be completed/i);
    expect(verificationErrorMessage(undefined)).toMatch(/could not be completed/i);
  });
});

describe('verificationPollingInterval', () => {
  it('disables the interval without a document (node test environment)', () => {
    // `typeof document` is the guard that keeps the interval safe to evaluate
    // outside a browser; it must return `false` rather than throw.
    expect(verificationPollingInterval()).toBe(false);
  });

  it('polls on the configured cadence only while the page is visible', () => {
    const scope = globalThis as unknown as { document?: { visibilityState: string } };
    const original = scope.document;

    try {
      scope.document = { visibilityState: 'visible' };
      expect(verificationPollingInterval()).toBe(VERIFICATION_POLL_INTERVAL_MS);

      scope.document = { visibilityState: 'hidden' };
      expect(verificationPollingInterval()).toBe(false);
    } finally {
      if (original === undefined) {
        delete scope.document;
      } else {
        scope.document = original;
      }
    }
  });
});
