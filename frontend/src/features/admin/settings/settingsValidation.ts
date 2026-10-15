import type { ResolvedSettingField } from './settingsSchema';

/**
 * Client-side validation for the settings form.
 *
 * This mirrors the rules the backend applies in `UpdateSettingsRequest` so the
 * administrator sees a problem before a request is made. It is deliberately the
 * *preview* half of the contract: the server is still authoritative and can
 * answer 422 for anything this lets through, which the save flow turns into an
 * error toast. Keeping the rules here — as pure functions over the same
 * registry-derived field definitions — is what makes them testable without a
 * browser and keeps the form and the server from disagreeing.
 *
 * The one deliberate difference is terminology: messages name the field by its
 * label so they read well inline, where the backend uses `:attribute`.
 */
export function validateSetting(field: ResolvedSettingField, value: string): string | null {
  if (field.readOnly) {
    return null;
  }

  if (field.required && value.trim() === '') {
    return `${field.label} is required.`;
  }

  if (value === '') {
    return null;
  }

  switch (field.type) {
    case 'email':
      return validateEmail(field, value);
    case 'integer':
      return validateNumber(field, value, true);
    case 'decimal':
      return validateNumber(field, value, false);
    default:
      return validateMaxLength(field, value);
  }
}

function validateEmail(field: ResolvedSettingField, value: string): string | null {
  if (!isValidEmail(value)) {
    return 'Enter a valid email address.';
  }

  return validateMaxLength(field, value);
}

function validateNumber(
  field: ResolvedSettingField,
  value: string,
  integer: boolean,
): string | null {
  if (!isNumeric(value)) {
    return 'Enter a number.';
  }

  if (integer && !/^-?\d+$/.test(value)) {
    return 'Enter a whole number.';
  }

  const number = Number(value);

  if (field.min !== undefined && number < field.min) {
    return `Must be at least ${field.min}.`;
  }

  if (field.max !== undefined && number > field.max) {
    return `Must not be greater than ${field.max}.`;
  }

  return null;
}

function validateMaxLength(field: ResolvedSettingField, value: string): string | null {
  if (field.maxLength !== undefined && value.length > field.maxLength) {
    return `Must not exceed ${field.maxLength} characters.`;
  }

  return null;
}

/**
 * A pragmatic email check. HTML5 email validation is intentionally loose, and
 * the backend's `FILTER_VALIDATE_EMAIL` is the real check; this only catches the
 * obvious mistakes before a round trip.
 */
export function isValidEmail(value: string): boolean {
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value);
}

/** Mirrors PHP's `is_numeric()` for the string values a form produces. */
export function isNumeric(value: string): boolean {
  return value.trim() !== '' && Number.isFinite(Number(value));
}

/** Validate every field, returning a map of key to the first error found. */
export function validateFields(
  fields: ResolvedSettingField[],
  values: Record<string, string>,
): Record<string, string> {
  const errors: Record<string, string> = {};

  for (const field of fields) {
    const error = validateSetting(field, values[field.key] ?? '');
    if (error !== null) {
      errors[field.key] = error;
    }
  }

  return errors;
}
