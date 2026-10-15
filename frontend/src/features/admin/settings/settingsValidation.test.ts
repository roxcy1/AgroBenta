import { describe, expect, it } from 'vitest';
import { validateFields, validateSetting } from './settingsValidation';
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

describe('validateSetting', () => {
  it('requires a required field to be non-empty after trimming', () => {
    const required = field({ required: true, label: 'System Name' });

    expect(validateSetting(required, '')).toBe('System Name is required.');
    expect(validateSetting(required, '   ')).toBe('System Name is required.');
    expect(validateSetting(required, 'AgroBenta')).toBeNull();
  });

  it('allows an optional field to be empty', () => {
    expect(validateSetting(field({ type: 'email' }), '')).toBeNull();
    expect(validateSetting(field({ type: 'integer', min: 1 }), '')).toBeNull();
  });

  it('rejects an invalid email and accepts a valid one', () => {
    const email = field({ type: 'email', maxLength: 255 });

    expect(validateSetting(email, 'not-an-email')).toBe('Enter a valid email address.');
    expect(validateSetting(email, 'admin@agrobenta.test')).toBeNull();
  });

  it('enforces maxLength for text and email', () => {
    expect(validateSetting(field({ maxLength: 5 }), 'abcdef')).toBe(
      'Must not exceed 5 characters.',
    );
    expect(validateSetting(field({ maxLength: 5 }), 'abcde')).toBeNull();
  });

  it('validates integers against whole-number and bounds', () => {
    const photos = field({ type: 'integer', min: 1, max: 50 });

    expect(validateSetting(photos, 'abc')).toBe('Enter a number.');
    expect(validateSetting(photos, '2.5')).toBe('Enter a whole number.');
    expect(validateSetting(photos, '0')).toBe('Must be at least 1.');
    expect(validateSetting(photos, '51')).toBe('Must not be greater than 50.');
    expect(validateSetting(photos, '10')).toBeNull();
  });

  it('validates decimals against bounds', () => {
    const price = field({ type: 'decimal', min: 0.01, max: 99999999999.99 });

    expect(validateSetting(price, 'nope')).toBe('Enter a number.');
    expect(validateSetting(price, '0')).toBe('Must be at least 0.01.');
    expect(validateSetting(price, '-5')).toBe('Must be at least 0.01.');
    expect(validateSetting(price, '1000000000000')).toBe('Must not be greater than 99999999999.99.');
    expect(validateSetting(price, '1500.50')).toBeNull();
  });

  it('skips read-only fields', () => {
    const readOnly = field({ required: true, readOnly: true });

    expect(validateSetting(readOnly, '')).toBeNull();
  });
});

describe('validateFields', () => {
  it('collects the first error per field', () => {
    const fields = [
      field({ key: 'system.name', label: 'System Name', required: true, value: '' }),
      field({ key: 'listing.max_photos', label: 'Max Photos', type: 'integer', min: 1, max: 50 }),
    ];

    const errors = validateFields(fields, {
      'system.name': '',
      'listing.max_photos': '51',
    });

    expect(errors).toEqual({
      'system.name': 'System Name is required.',
      'listing.max_photos': 'Must not be greater than 50.',
    });
  });

  it('returns no errors when every value is valid', () => {
    const fields = [
      field({ key: 'system.name', required: true }),
      field({ key: 'listing.max_photos', type: 'integer', min: 1, max: 50 }),
    ];

    expect(
      validateFields(fields, { 'system.name': 'AgroBenta', 'listing.max_photos': '10' }),
    ).toEqual({});
  });
});
