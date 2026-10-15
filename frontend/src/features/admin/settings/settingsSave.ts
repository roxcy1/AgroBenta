import type { ResolvedSettingField } from './settingsSchema';
import { buildPayload, computeChanges, resolveValues } from './settingsChanges';
import type { SettingChange } from './settingsChanges';
import { validateFields } from './settingsValidation';

/**
 * Everything the save button needs to decide, derived purely from the fields
 * and the administrator's edits.
 */
export interface SavePlan {
  /** First validation error per field key, empty when the form is valid. */
  errors: Record<string, string>;
  /** Fields whose value differs from the original, in field order. */
  changes: SettingChange[];
  /** The flat body for `PUT /api/admin/settings` — only the changed keys. */
  payload: Record<string, string>;
  /** True only when the form is valid and at least one field changed. */
  canSave: boolean;
}

/**
 * Plan a save without touching the network.
 *
 * `canSave` is false when anything is invalid or nothing changed, in which case
 * the page opens no confirmation and sends no request. Because the payload is
 * built from `changes`, a partial form is never submitted and unedited settings
 * are never overwritten.
 */
export function planSave(
  fields: ResolvedSettingField[],
  edits: Record<string, string>,
): SavePlan {
  const values = resolveValues(fields, edits);
  const errors = validateFields(fields, values);
  const changes = computeChanges(fields, edits);
  const payload = buildPayload(changes);

  return {
    errors,
    changes,
    payload,
    canSave: Object.keys(errors).length === 0 && changes.length > 0,
  };
}

/** The confirmation dialog's state. */
export interface SaveDialogState {
  open: boolean;
  pending: boolean;
}

export const initialSaveDialogState: SaveDialogState = { open: false, pending: false };

export type SaveAction = 'request' | 'cancel' | 'submit' | 'settle';

/** The only side effect the state machine can ask for. */
export type SaveEffect = 'none' | 'save';

/**
 * The confirmation dialog as a pure transition.
 *
 * Reducing the dialog to (state, action) -> (state, effect) makes the two rules
 * that matter testable without a browser:
 *
 * - `cancel` never asks for a `save`, so canceling makes no request;
 * - `submit` while a save is `pending` is ignored, so a slow connection cannot
 *   produce a duplicate request.
 *
 * The page performs the mutation only when the returned effect is `save`.
 */
export function nextSaveState(
  state: SaveDialogState,
  action: SaveAction,
): { state: SaveDialogState; effect: SaveEffect } {
  switch (action) {
    case 'request':
      return state.pending
        ? { state, effect: 'none' }
        : { state: { open: true, pending: false }, effect: 'none' };
    case 'cancel':
      return state.pending
        ? { state, effect: 'none' }
        : { state: initialSaveDialogState, effect: 'none' };
    case 'submit':
      return state.open && !state.pending
        ? { state: { open: true, pending: true }, effect: 'save' }
        : { state, effect: 'none' };
    case 'settle':
      return { state: initialSaveDialogState, effect: 'none' };
  }
}
