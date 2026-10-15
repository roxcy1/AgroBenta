import { describe, expect, it } from 'vitest';
import { buildSections, flattenFields } from './settingsSchema';
import type { SettingsData } from './api/useSettings';

function fieldValue(sections: ReturnType<typeof buildSections>, sectionId: string, key: string) {
  const section = sections.find((candidate) => candidate.id === sectionId);
  return section?.fields.find((field) => field.key === key);
}

describe('buildSections', () => {
  it('returns every section when the API has no data', () => {
    const sections = buildSections(undefined);

    expect(sections.map((section) => section.id)).toEqual([
      'system',
      'admin_contact',
      'listings',
      'verification',
    ]);
  });

  it('declares all eight registry keys', () => {
    const keys = flattenFields(buildSections(undefined)).map((field) => field.key);

    expect(keys).toEqual([
      'system.name',
      'system.description',
      'admin_contact.name',
      'admin_contact.email',
      'admin_contact.phone',
      'listing.max_photos',
      'listing.max_price',
      'verification.guidance',
    ]);
  });

  it('falls back to documented defaults when keys are missing', () => {
    const sections = buildSections(undefined);

    expect(fieldValue(sections, 'system', 'system.name')).toMatchObject({
      value: 'AgroBenta',
      isDefault: true,
    });
    expect(fieldValue(sections, 'system', 'system.description')).toMatchObject({
      value: 'A livestock trading platform connecting buyers and sellers.',
      isDefault: true,
    });
    expect(fieldValue(sections, 'admin_contact', 'admin_contact.name')).toMatchObject({
      value: 'Administrator',
      isDefault: true,
    });
    expect(fieldValue(sections, 'listings', 'listing.max_photos')).toMatchObject({
      value: '10',
      isDefault: true,
    });
    expect(fieldValue(sections, 'listings', 'listing.max_price')).toMatchObject({
      value: '99999999999.99',
      isDefault: true,
    });
  });

  it('carries the bounds the registry enforces', () => {
    const sections = buildSections(undefined);

    expect(fieldValue(sections, 'listings', 'listing.max_photos')).toMatchObject({
      type: 'integer',
      min: 1,
      max: 50,
    });
    expect(fieldValue(sections, 'listings', 'listing.max_price')).toMatchObject({
      type: 'decimal',
      min: 0.01,
      max: 99999999999.99,
    });
    expect(fieldValue(sections, 'system', 'system.name')).toMatchObject({
      required: true,
      maxLength: 255,
    });
  });

  it('uses the API value when the key is present', () => {
    const data: SettingsData = {
      system: [
        {
          key: 'system.name',
          value: 'AgroBenta PH',
          group: 'system',
          label: 'System Name',
          description: 'The display name of the platform.',
        },
      ],
    };

    const sections = buildSections(data);
    const name = fieldValue(sections, 'system', 'system.name');

    expect(name).toMatchObject({
      value: 'AgroBenta PH',
      label: 'System Name',
      isDefault: false,
    });
  });

  it('prefers the API label and description for keys it returns', () => {
    const data: SettingsData = {
      admin_contact: [
        {
          key: 'admin_contact.email',
          value: 'support@agrobenta.test',
          group: 'admin_contact',
          label: 'Support Email',
          description: null,
        },
      ],
    };

    const email = fieldValue(buildSections(data), 'admin_contact', 'admin_contact.email');

    expect(email?.label).toBe('Support Email');
    expect(email?.value).toBe('support@agrobenta.test');
  });

  it('marks the verification section empty when guidance has no value', () => {
    const sections = buildSections(undefined);
    const verification = sections.find((section) => section.id === 'verification');

    expect(verification?.isEmpty).toBe(true);
    expect(verification?.emptyMessage).toBe('No verification guidance configured.');
  });

  it('is not empty once guidance has a value', () => {
    const data: SettingsData = {
      verification: [
        {
          key: 'verification.guidance',
          value: 'Provide a valid business permit.',
          group: 'verification',
          label: 'Verification Guidance',
          description: null,
        },
      ],
    };

    const verification = buildSections(data).find((section) => section.id === 'verification');

    expect(verification?.isEmpty).toBe(false);
  });
});
