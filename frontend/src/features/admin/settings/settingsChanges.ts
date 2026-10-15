import type { ResolvedSettingField } from './settingsSchema';

/**
 * The diff between what the API returned and what the administrator has typed.
 *
 * The form keeps `edits` as a sparse map of only the fields actually touched.
 * A field is "changed" when its edited value differs from the value the API
 * returned (or the documented default, for a key the API does not return yet).
 * Everything that is not changed is left alone, so a save can never overwrite a
 * setting the administrator did not touch — and, because only known fields are
 * considered, a key the frontend does not know is never submitted either.
 */
export interface SettingChange {
  key: string;
  label: string;
  oldValue: string;
  newValue: string;
}

/**
 * The value each field is currently showing for validation and diffing:
 * the edited value when present, otherwise the original.
 */
export function resolveValues(
  fields: ResolvedSettingField[],
  edits: Record<string, string>,
): Record<string, string> {
  const values: Record<string, string> = {};

  for (const field of fields) {
    values[field.key] = edits[field.key] ?? field.value;
  }

  return values;
}

/**
 * Every field whose resolved value differs from the original, in field order.
 *
 * A missing key resolves to its documented default, so a default that is left
 * untouched is not a change; only typing over it makes it one.
 */
export function computeChanges(
  fields: ResolvedSettingField[],
  edits: Record<string, string>,
): SettingChange[] {
  const changes: SettingChange[] = [];

  for (const field of fields) {
    const newValue = edits[field.key] ?? field.value;

    if (newValue !== field.value) {
      changes.push({
        key: field.key,
        label: field.label,
        oldValue: field.value,
        newValue,
      });
    }
  }

  return changes;
}

/**
 * The flat `key => value` body for `PUT /api/admin/settings`.
 *
 * Built only from the changes, so it contains exactly the keys the
 * administrator edited and never a partially filled or unknown field.
 */
export function buildPayload(changes: SettingChange[]): Record<string, string> {
  const payload: Record<string, string> = {};

  for (const change of changes) {
    payload[change.key] = change.newValue;
  }

  return payload;
}

/** How an empty value reads in the confirmation dialog. */
export function formatChangeValue(value: string): string {
  return value === '' ? 'Not set' : value;
}
