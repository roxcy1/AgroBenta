import { describe, expect, it } from 'vitest';
import { statusChartColor, statusLabel, statusTone } from './status';

describe('statusLabel', () => {
  it('names every status the Admin Web shows', () => {
    expect(
      [
        'draft',
        'pending',
        'active',
        'sold',
        'inactive',
        'submitted',
        'pending_review',
        'approved',
        'rejected',
        'completed',
        'cancelled',
      ].map(statusLabel),
    ).toEqual([
      'Draft',
      'Pending',
      'Active',
      'Sold',
      'Inactive',
      'Submitted',
      'Pending Review',
      'Approved',
      'Rejected',
      'Completed',
      'Cancelled',
    ]);
  });

  it('humanizes a status it has not been taught instead of showing the raw value', () => {
    expect(statusLabel('awaiting_pickup')).toBe('Awaiting Pickup');
  });
});

describe('statusTone', () => {
  it('uses one tone per meaning, whatever the page', () => {
    expect(statusTone('pending')).toBe('warning');
    expect(statusTone('pending_review')).toBe('warning');
    expect(statusTone('active')).toBe('success');
    expect(statusTone('approved')).toBe('success');
    expect(statusTone('completed')).toBe('success');
    expect(statusTone('rejected')).toBe('danger');
    expect(statusTone('cancelled')).toBe('danger');
    expect(statusTone('draft')).toBe('neutral');
    expect(statusTone('inactive')).toBe('neutral');
    expect(statusTone('sold')).toBe('info');
  });

  it('falls back to neutral', () => {
    expect(statusTone('something_new')).toBe('neutral');
  });
});

describe('statusChartColor', () => {
  it('returns a CSS variable, never a hard-coded hex value', () => {
    for (const status of ['draft', 'pending', 'active', 'sold', 'inactive', 'rejected', 'x']) {
      expect(statusChartColor(status)).toMatch(/^var\(--[a-z-]+\)$/);
    }
  });

  it('keeps Draft and Inactive apart so a pie chart can tell them apart', () => {
    expect(statusChartColor('draft')).not.toBe(statusChartColor('inactive'));
  });
});
