import type { AxiosError } from 'axios';

/**
 * The messages the settings form shows after a save.
 *
 * Mirrors the livestock and verification `...ErrorMessage()` contracts: a
 * failed request becomes a short, actionable sentence. A 422 is the interesting
 * one — the server rejected a value the client preview let through — so it
 * points back at the form rather than suggesting a retry.
 */
export function settingsErrorMessage(error: unknown): string {
  const status = (error as AxiosError<{ message?: string }>)?.response?.status;

  switch (status) {
    case 403:
      return 'You do not have permission to change settings.';
    case 422:
      return 'The settings were rejected as invalid. Review the form and try again.';
    case 500:
      return 'The server could not save the settings. Please try again.';
    default:
      return 'The settings could not be saved. Check your connection and try again.';
  }
}

/** The success toast for a save the server accepted in full. */
export function settingsSuccessMessage(updated: string[]): string {
  const count = updated.length;
  return count === 1 ? 'Saved 1 setting.' : `Saved ${count} settings.`;
}

/**
 * The toast for a save the server accepted while ignoring some keys.
 *
 * The HTTP call succeeded (200), but the contract reports unknown keys in
 * `rejected` rather than failing the request, so this is an error toast: part
 * of what the administrator submitted was not applied.
 */
export function settingsRejectedMessage(rejected: string[]): string {
  const noun = rejected.length === 1 ? 'setting' : 'settings';
  return `The server did not recognise ${noun}: ${rejected.join(', ')}.`;
}
