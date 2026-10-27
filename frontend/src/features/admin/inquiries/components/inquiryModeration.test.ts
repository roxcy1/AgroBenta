import { describe, expect, it } from 'vitest';
import {
  INQUIRY_STATUSES,
  INQUIRY_STATUS_FILTER_OPTIONS,
  contactMethodLabel,
  inquiryErrorMessage,
  statusBadgeClass,
  statusBadgeModifier,
  statusLabel,
  transactionMethodLabel,
} from './inquiryModeration';

describe('INQUIRY_STATUSES', () => {
  it('covers exactly the three documented states, in order', () => {
    expect(INQUIRY_STATUSES.map((entry) => entry.value)).toEqual([
      'open',
      'responded',
      'closed',
    ]);
  });

  it('gives every status a non-empty label', () => {
    for (const entry of INQUIRY_STATUSES) {
      expect(entry.label.length).toBeGreaterThan(0);
    }
  });
});

describe('INQUIRY_STATUS_FILTER_OPTIONS', () => {
  it('offers an "all" option followed by every status', () => {
    expect(INQUIRY_STATUS_FILTER_OPTIONS.map((option) => option.value)).toEqual([
      '',
      'open',
      'responded',
      'closed',
    ]);
  });
});

describe('statusLabel', () => {
  it('labels the known states', () => {
    expect(statusLabel('open')).toBe('Open');
    expect(statusLabel('responded')).toBe('Responded');
    expect(statusLabel('closed')).toBe('Closed');
  });

  it('renders an unknown status as itself rather than blank', () => {
    expect(statusLabel('archived')).toBe('Archived');
  });
});

describe('statusBadgeModifier', () => {
  it('maps each state to an existing stylesheet modifier', () => {
    expect(statusBadgeModifier('open')).toBe('pending');
    expect(statusBadgeModifier('responded')).toBe('active');
    expect(statusBadgeModifier('closed')).toBe('inactive');
  });

  it('falls back to a neutral modifier for an unknown status', () => {
    expect(statusBadgeModifier('archived')).toBe('inactive');
  });
});

describe('statusBadgeClass', () => {
  it('builds a badge class that carries the shared base class', () => {
    expect(statusBadgeClass('open')).toBe('lv-badge lv-badge--pending');
    expect(statusBadgeClass('responded')).toBe('lv-badge lv-badge--active');
    expect(statusBadgeClass('closed')).toBe('lv-badge lv-badge--inactive');
  });

  it('falls back to the inactive modifier for an unknown status', () => {
    expect(statusBadgeClass('archived')).toBe('lv-badge lv-badge--inactive');
  });
});

describe('transactionMethodLabel', () => {
  it('labels the two documented methods', () => {
    expect(transactionMethodLabel('direct_deal')).toBe('Direct Deal');
    expect(transactionMethodLabel('arrange_delivery')).toBe('Arrange Delivery');
  });

  it('renders an absent value as a dash', () => {
    expect(transactionMethodLabel(null)).toBe('\u2014');
    expect(transactionMethodLabel(undefined)).toBe('\u2014');
  });

  it('renders an unknown value as itself', () => {
    expect(transactionMethodLabel('escrow')).toBe('escrow');
  });
});

describe('contactMethodLabel', () => {
  it('labels the only documented contact method', () => {
    expect(contactMethodLabel('in_app_message')).toBe('In-App Message');
  });

  it('renders an absent value as a dash', () => {
    expect(contactMethodLabel(null)).toBe('\u2014');
    expect(contactMethodLabel(undefined)).toBe('\u2014');
  });
});

describe('inquiryErrorMessage', () => {
  const axiosError = (status: number) => ({ response: { status } });

  it('maps 403 to a permission message', () => {
    expect(inquiryErrorMessage(axiosError(403))).toMatch(/permission/i);
  });

  it('maps 404 to a missing-record message', () => {
    expect(inquiryErrorMessage(axiosError(404))).toMatch(/no longer exists/i);
  });

  it('maps 422 to a validation message', () => {
    expect(inquiryErrorMessage(axiosError(422))).toMatch(/status/i);
  });

  it('maps 500 to a server message', () => {
    expect(inquiryErrorMessage(axiosError(500))).toMatch(/server/i);
  });

  it('falls back for an unknown status or non-axios error', () => {
    expect(inquiryErrorMessage(axiosError(418))).toMatch(/went wrong/i);
    expect(inquiryErrorMessage(new Error('boom'))).toMatch(/went wrong/i);
  });
});
