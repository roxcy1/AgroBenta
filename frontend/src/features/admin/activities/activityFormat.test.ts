import { describe, expect, it } from 'vitest';
import {
  ACTIVITY_ACTION_OPTIONS,
  activityActionLabel,
  activityActorLabel,
  activityChanges,
  activityContextEntries,
  activityTargetLabel,
  activityTimestampTitle,
  emptyActivitiesMessage,
  formatActivityTimestamp,
  formatMetadataValue,
  getActivityTargetLink,
  hasActiveActivityFilters,
  humanizeLabel,
} from './activityFormat';

describe('humanizeLabel', () => {
  it('turns snake_case into title case', () => {
    expect(humanizeLabel('listing_approved')).toBe('Listing Approved');
  });

  it('handles dashes and mixed separators', () => {
    expect(humanizeLabel('photo-removed')).toBe('Photo Removed');
  });

  it('returns a dash for empty input', () => {
    expect(humanizeLabel('')).toBe('\u2014');
  });
});

describe('activityActionLabel', () => {
  it('humanizes a known action', () => {
    expect(activityActionLabel('seller_verification_approved')).toBe(
      'Seller Verification Approved',
    );
  });

  it('humanizes an unknown action rather than hiding it', () => {
    expect(activityActionLabel('custom_event')).toBe('Custom Event');
  });

  it('falls back for a blank action', () => {
    expect(activityActionLabel('   ')).toBe('Unknown action');
    expect(activityActionLabel('')).toBe('Unknown action');
  });
});

describe('ACTIVITY_ACTION_OPTIONS', () => {
  it('offers an "all actions" default and the canonical actions', () => {
    expect(ACTIVITY_ACTION_OPTIONS[0]).toEqual({ value: '', label: 'All Actions' });
    expect(ACTIVITY_ACTION_OPTIONS.map((option) => option.value)).toContain('listing_approved');
    expect(ACTIVITY_ACTION_OPTIONS.map((option) => option.value)).toContain('settings_updated');
  });

  it('has unique action values', () => {
    const values = ACTIVITY_ACTION_OPTIONS.map((option) => option.value);
    expect(new Set(values).size).toBe(values.length);
  });

  it('offers the listing photo added action and formats its label', () => {
    expect(ACTIVITY_ACTION_OPTIONS).toContainEqual({
      value: 'listing_photo_added',
      label: 'Listing photo added',
    });
    expect(activityActionLabel('listing_photo_added')).toBe('Listing Photo Added');
  });
});

describe('activityActorLabel', () => {
  it('uses the user name', () => {
    expect(activityActorLabel({ name: 'Juan' })).toBe('Juan');
  });

  it('falls back to System for a missing or blank actor', () => {
    expect(activityActorLabel(null)).toBe('System');
    expect(activityActorLabel(undefined)).toBe('System');
    expect(activityActorLabel({ name: '   ' })).toBe('System');
  });
});

describe('formatMetadataValue', () => {
  it('renders an em dash for empty values', () => {
    expect(formatMetadataValue(null)).toBe('\u2014');
    expect(formatMetadataValue(undefined)).toBe('\u2014');
    expect(formatMetadataValue('')).toBe('\u2014');
    expect(formatMetadataValue([])).toBe('\u2014');
  });

  it('stringifies primitives and arrays', () => {
    expect(formatMetadataValue(5)).toBe('5');
    expect(formatMetadataValue(true)).toBe('true');
    expect(formatMetadataValue(['a', 'b'])).toBe('a, b');
  });

  it('serializes objects as JSON', () => {
    expect(formatMetadataValue({ a: 1 })).toBe('{"a":1}');
  });
});

describe('activityTargetLabel', () => {
  it('combines the target type and id', () => {
    expect(activityTargetLabel({ target_type: 'listing', target_id: 5 })).toBe('Listing #5');
  });

  it('handles a type without an id and an id without a type', () => {
    expect(activityTargetLabel({ target_type: 'setting' })).toBe('Setting');
    expect(activityTargetLabel({ target_id: 9 })).toBe('#9');
  });

  it('renders an em dash when no target is recorded', () => {
    expect(activityTargetLabel(null)).toBe('\u2014');
    expect(activityTargetLabel({})).toBe('\u2014');
  });
});

describe('activityChanges', () => {
  it('extracts each field change with a label and formatted values', () => {
    const changes = activityChanges({
      changes: {
        status: { from: 'pending', to: 'active' },
        photos: { from: 2, to: 3 },
      },
    });

    expect(changes).toEqual([
      { field: 'status', label: 'Status', from: 'pending', to: 'active' },
      { field: 'photos', label: 'Photos', from: '2', to: '3' },
    ]);
  });

  it('renders null sides as an em dash', () => {
    const changes = activityChanges({ changes: { status: { from: 'draft', to: null } } });
    expect(changes).toEqual([
      { field: 'status', label: 'Status', from: 'draft', to: '\u2014' },
    ]);
  });

  it('ignores malformed change entries and missing metadata', () => {
    expect(activityChanges(null)).toEqual([]);
    expect(activityChanges({})).toEqual([]);
    expect(activityChanges({ changes: { status: 'active' } })).toEqual([]);
    expect(activityChanges({ changes: { status: { from: 'a' } } })).toEqual([]);
  });
});

describe('activityContextEntries', () => {
  it('returns the context entries with humanized labels', () => {
    const entries = activityContextEntries({
      context: { seller_id: 4, livestock_type: 'cattle' },
    });

    expect(entries).toEqual([
      { field: 'seller_id', label: 'Seller Id', value: '4' },
      { field: 'livestock_type', label: 'Livestock Type', value: 'cattle' },
    ]);
  });

  it('drops sensitive keys', () => {
    const entries = activityContextEntries({
      context: {
        guard: 'admin',
        password: 'secret',
        access_token: 'abc',
        api_key: 'xyz',
      },
    });

    expect(entries.map((entry) => entry.field)).toEqual(['guard']);
  });

  it('returns an empty list when there is no context', () => {
    expect(activityContextEntries(null)).toEqual([]);
    expect(activityContextEntries({})).toEqual([]);
  });
});

describe('hasActiveActivityFilters', () => {
  it('is false when nothing is set', () => {
    expect(hasActiveActivityFilters({})).toBe(false);
  });

  it('is true when any filter is set', () => {
    expect(hasActiveActivityFilters({ search: 'x' })).toBe(true);
    expect(hasActiveActivityFilters({ action: 'listing_approved' })).toBe(true);
    expect(hasActiveActivityFilters({ user_id: 1 })).toBe(true);
    expect(hasActiveActivityFilters({ date_from: '2026-01-01' })).toBe(true);
    expect(hasActiveActivityFilters({ date_to: '2026-01-31' })).toBe(true);
  });
});

describe('emptyActivitiesMessage', () => {
  it('distinguishes filtered from unfiltered empty states', () => {
    expect(emptyActivitiesMessage(true)).toBe('No activities match the current filters.');
    expect(emptyActivitiesMessage(false)).toBe('No activities have been recorded yet.');
  });
});

describe('getActivityTargetLink', () => {
  it('links each supported target type to its page with the id as a query param', () => {
    expect(getActivityTargetLink({ target_type: 'listing', target_id: 5 })).toEqual({
      href: '/livestock?listing=5',
      label: 'Listing #5',
    });
    expect(getActivityTargetLink({ target_type: 'transaction', target_id: 7 })).toEqual({
      href: '/transactions?transaction=7',
      label: 'Transaction #7',
    });
    expect(getActivityTargetLink({ target_type: 'seller_verification', target_id: 3 })).toEqual({
      href: '/seller-verification?verification=3',
      label: 'Verification #3',
    });
    expect(getActivityTargetLink({ target_type: 'user', target_id: 9 })).toEqual({
      href: '/users?user=9',
      label: 'User #9',
    });
  });

  it('links settings without an id', () => {
    expect(getActivityTargetLink({ target_type: 'setting' })).toEqual({
      href: '/settings',
      label: 'Settings',
    });
  });

  it('accepts a string id and trims it', () => {
    expect(getActivityTargetLink({ target_type: 'listing', target_id: ' 12 ' })).toEqual({
      href: '/livestock?listing=12',
      label: 'Listing #12',
    });
  });

  it('returns no href for unknown or incomplete targets', () => {
    expect(getActivityTargetLink(null)).toEqual({ href: null, label: '\u2014' });
    expect(getActivityTargetLink({})).toEqual({ href: null, label: '\u2014' });
    expect(getActivityTargetLink({ target_type: 'listing' })).toEqual({
      href: null,
      label: 'Listing',
    });
    expect(getActivityTargetLink({ target_type: 'invoice', target_id: 4 })).toEqual({
      href: null,
      label: 'Invoice #4',
    });
  });
});

describe('timestamp helpers', () => {
  it('formats a valid timestamp and returns an em dash for invalid input', () => {
    expect(formatActivityTimestamp('2026-01-02T03:04:05.000000Z')).not.toBe('\u2014');
    expect(formatActivityTimestamp('not-a-date')).toBe('\u2014');
  });

  it('returns the raw value as the title when the date is invalid', () => {
    expect(activityTimestampTitle('not-a-date')).toBe('not-a-date');
    expect(activityTimestampTitle('2026-01-02T03:04:05.000000Z')).not.toBe('not-a-date');
  });
});
