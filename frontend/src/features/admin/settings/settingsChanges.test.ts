import { describe, expect, it } from 'vitest';
import { buildPayload, computeChanges, formatChangeValue, resolveValues } from './settingsChanges';
import type { ResolvedSettingField } from './settingsSchema';

function field(overrides: Partial<ResolvedSettingField>): ResolvedSettingField {
  return {
    key: 'test.key',
    label: 'Test Field',
    type: 'text',
    default: '',
    value: '',
    description: null,
    isDefault: false,
    ...overrides,
  };
}

describe('resolveValues', () => {
  it('uses the edit when present and the original otherwise', () => {
    const fields = [
      field({ key: 'system.name', value: 'AgroBenta' }),
      field({ key: 'admin_contact.phone', value: '' }),
    ];

    expect(resolveValues(fields, { 'admin_contact.phone': '0917' })).toEqual({
      'system.name': 'AgroBenta',
      'admin_contact.phone': '0917',
    });
  });
});

describe('computeChanges', () => {
  it('returns nothing when no field was edited', () => {
    const fields = [field({ key: 'listing.max_photos', value: '10', default: '10', isDefault: true })];

    expect(computeChanges(fields, {})).toEqual([]);
  });

  it('reports a changed field with its old and new value', () => {
    const fields = [field({ key: 'system.name', label: 'System Name', value: 'AgroBenta' })];

    expect(computeChanges(fields, { 'system.name': 'AgroBenta PH' })).toEqual([
      {
        key: 'system.name',
        label: 'System Name',
        oldValue: 'AgroBenta',
        newValue: 'AgroBenta PH',
      },
    ]);
  });

  it('treats an untouched default as unchanged and an edited default as changed', () => {
    const fields = [
      field({ key: 'listing.max_photos', value: '10', default: '10', isDefault: true }),
    ];

    expect(computeChanges(fields, {})).toEqual([]);
    expect(computeChanges(fields, { 'listing.max_photos': '20' })).toHaveLength(1);
  });

  it('ignores edits for keys the page does not know', () => {
    const fields = [field({ key: 'system.name', value: 'AgroBenta' })];

    expect(computeChanges(fields, { 'unknown.key': 'x' })).toEqual([]);
  });

  it('treats an edit equal to the original as no change', () => {
    const fields = [field({ key: 'system.name', value: 'AgroBenta' })];

    expect(computeChanges(fields, { 'system.name': 'AgroBenta' })).toEqual([]);
  });
});

describe('buildPayload', () => {
  it('includes only the changed keys', () => {
    const payload = buildPayload([
      {
        key: 'system.name',
        label: 'System Name',
        oldValue: 'AgroBenta',
        newValue: 'AgroBenta PH',
      },
      {
        key: 'listing.max_photos',
        label: 'Max Photos',
        oldValue: '10',
        newValue: '20',
      },
    ]);

    expect(payload).toEqual({ 'system.name': 'AgroBenta PH', 'listing.max_photos': '20' });
  });

  it('is empty when there are no changes', () => {
    expect(buildPayload([])).toEqual({});
  });
});

describe('formatChangeValue', () => {
  it('labels an empty value as not set', () => {
    expect(formatChangeValue('')).toBe('Not set');
    expect(formatChangeValue('10')).toBe('10');
  });
});
