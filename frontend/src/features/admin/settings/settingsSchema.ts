import type { SettingsData } from './api/useSettings';

export type SettingType = 'text' | 'email' | 'integer' | 'decimal';

/** A setting the admin settings page knows about, with its documented default. */
export interface SettingFieldDefinition {
  key: string;
  label: string;
  type: SettingType;
  default: string;
  description?: string;
  /** A required field must not be submitted empty. `system.name` is the only one. */
  required?: boolean;
  /** Long-form text; rendered as a textarea rather than a single-line input. */
  multiline?: boolean;
  /** Inclusive lower bound for `integer` and `decimal` values. */
  min?: number;
  /** Inclusive upper bound for `integer` and `decimal` values. */
  max?: number;
  /** Maximum character length for `text` and `email` values. */
  maxLength?: number;
  /**
   * Read-only fields are informational and never editable. No current setting is
   * read-only, but the flag is kept so a future key can opt out of editing.
   */
  readOnly?: boolean;
}

export interface SettingSectionDefinition {
  id: string;
  title: string;
  fields: SettingFieldDefinition[];
  /** Shown when every field in the section has no value at all. */
  emptyMessage?: string;
}

/** A definition merged with whatever the API actually returned. */
export interface ResolvedSettingField extends Omit<SettingFieldDefinition, 'description'> {
  value: string;
  description: string | null;
  /** True when the API did not return this key and the documented default is shown. */
  isDefault: boolean;
}

export interface ResolvedSettingSection {
  id: string;
  title: string;
  fields: ResolvedSettingField[];
  emptyMessage?: string;
  isEmpty: boolean;
}

/**
 * The settings sections the admin page presents.
 *
 * The sections mirror the backend registry groups (`config/settings.php`), and
 * the key names, defaults and bounds are declared here so the form can validate
 * before submitting and render a documented default for a key the backend has
 * not returned yet. The backend stays authoritative: when it returns a key the
 * real value, label and description win and `isDefault` becomes false.
 */
export const SETTINGS_SECTIONS: SettingSectionDefinition[] = [
  {
    id: 'system',
    title: 'General',
    fields: [
      {
        key: 'system.name',
        label: 'System Name',
        type: 'text',
        default: 'AgroBenta',
        description: 'The display name of the platform.',
        required: true,
        maxLength: 255,
      },
      {
        key: 'system.description',
        label: 'System Description',
        type: 'text',
        default: 'A livestock trading platform connecting buyers and sellers.',
        description: 'A brief description of the platform.',
        multiline: true,
        maxLength: 1000,
      },
    ],
  },
  {
    id: 'admin_contact',
    title: 'Admin Contact',
    fields: [
      {
        key: 'admin_contact.name',
        label: 'Contact Name',
        type: 'text',
        default: 'Administrator',
        description: 'Name displayed as the platform contact.',
        maxLength: 255,
      },
      {
        key: 'admin_contact.email',
        label: 'Contact Email',
        type: 'email',
        default: 'admin@agrobenta.example.com',
        description: 'Email address for platform inquiries.',
        maxLength: 255,
      },
      {
        key: 'admin_contact.phone',
        label: 'Contact Phone',
        type: 'text',
        default: '',
        description: 'Phone number for platform inquiries.',
        maxLength: 50,
      },
    ],
  },
  {
    id: 'listings',
    title: 'Listings',
    fields: [
      {
        key: 'listing.max_photos',
        label: 'Maximum Photos per Listing',
        type: 'integer',
        default: '10',
        description: 'The most photos a single listing may hold.',
        min: 1,
        max: 50,
      },
      {
        key: 'listing.max_price',
        label: 'Maximum Asking Price',
        type: 'decimal',
        default: '99999999999.99',
        description: 'The highest asking price a listing may be given.',
        min: 0.01,
        max: 99999999999.99,
      },
    ],
  },
  {
    id: 'verification',
    title: 'Verification',
    fields: [
      {
        key: 'verification.guidance',
        label: 'Verification Guidance',
        type: 'text',
        default: '',
        description: 'Guidance shown to sellers when submitting verification.',
        multiline: true,
        maxLength: 2000,
      },
    ],
    emptyMessage: 'No verification guidance configured.',
  },
];

/**
 * Merge the API response over the section definitions.
 *
 * Never throws and never returns a blank field: a key missing from the API
 * falls back to the documented default. The API's own label and description
 * are used when present, so the backend stays authoritative for keys it owns.
 */
export function buildSections(data: SettingsData | undefined): ResolvedSettingSection[] {
  const byKey = new Map<string, { value: string; label: string; description: string | null }>();

  if (data) {
    for (const group of Object.values(data)) {
      for (const setting of group) {
        byKey.set(setting.key, {
          value: setting.value,
          label: setting.label,
          description: setting.description,
        });
      }
    }
  }

  return SETTINGS_SECTIONS.map((section) => {
    const fields: ResolvedSettingField[] = section.fields.map((field) => {
      const setting = byKey.get(field.key);

      return {
        ...field,
        label: setting?.label ?? field.label,
        value: setting ? setting.value : field.default,
        description: setting?.description ?? field.description ?? null,
        isDefault: setting === undefined,
      };
    });

    return {
      ...section,
      fields,
      isEmpty: fields.every((field) => field.value === ''),
    };
  });
}

/** Every resolved field across every section, flattened. */
export function flattenFields(sections: ResolvedSettingSection[]): ResolvedSettingField[] {
  return sections.flatMap((section) => section.fields);
}
