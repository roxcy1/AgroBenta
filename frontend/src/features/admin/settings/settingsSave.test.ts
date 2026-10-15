import { describe, expect, it } from 'vitest';
import {
  initialSaveDialogState,
  nextSaveState,
  planSave,
} from './settingsSave';
import type { SaveDialogState } from './settingsSave';
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

const fields: ResolvedSettingField[] = [
  field({ key: 'system.name', label: 'System Name', required: true, value: 'AgroBenta' }),
  field({
    key: 'listing.max_photos',
    label: 'Max Photos',
    type: 'integer',
    min: 1,
    max: 50,
    value: '10',
  }),
];

describe('planSave', () => {
  it('cannot save when nothing changed', () => {
    const plan = planSave(fields, {});

    expect(plan.canSave).toBe(false);
    expect(plan.changes).toEqual([]);
    expect(plan.payload).toEqual({});
    expect(plan.errors).toEqual({});
  });

  it('can save a valid changed field and builds the payload from the diff', () => {
    const plan = planSave(fields, { 'listing.max_photos': '20' });

    expect(plan.canSave).toBe(true);
    expect(plan.payload).toEqual({ 'listing.max_photos': '20' });
    expect(plan.errors).toEqual({});
  });

  it('cannot save an invalid form and reports the field error', () => {
    const plan = planSave(fields, { 'system.name': '' });

    expect(plan.canSave).toBe(false);
    expect(plan.errors).toEqual({ 'system.name': 'System Name is required.' });
  });

  it('never includes an untouched field in the payload', () => {
    const plan = planSave(fields, { 'system.name': 'AgroBenta PH' });

    expect(plan.payload).toEqual({ 'system.name': 'AgroBenta PH' });
    expect(plan.payload).not.toHaveProperty('listing.max_photos');
  });
});

describe('nextSaveState', () => {
  it('opens the confirmation on request without saving', () => {
    const { state, effect } = nextSaveState(initialSaveDialogState, 'request');

    expect(state).toEqual({ open: true, pending: false });
    expect(effect).toBe('none');
  });

  it('canceling closes the dialog and makes no request', () => {
    const open: SaveDialogState = { open: true, pending: false };
    const { state, effect } = nextSaveState(open, 'cancel');

    expect(state).toEqual(initialSaveDialogState);
    expect(effect).toBe('none');
  });

  it('submitting an open dialog asks for exactly one save', () => {
    const open: SaveDialogState = { open: true, pending: false };
    const { state, effect } = nextSaveState(open, 'submit');

    expect(state).toEqual({ open: true, pending: true });
    expect(effect).toBe('save');
  });

  it('ignores a duplicate submit while a save is pending', () => {
    const pending: SaveDialogState = { open: true, pending: true };
    const { state, effect } = nextSaveState(pending, 'submit');

    expect(state).toEqual(pending);
    expect(effect).toBe('none');
  });

  it('ignores cancel and request while a save is pending', () => {
    const pending: SaveDialogState = { open: true, pending: true };

    expect(nextSaveState(pending, 'cancel')).toEqual({ state: pending, effect: 'none' });
    expect(nextSaveState(pending, 'request')).toEqual({ state: pending, effect: 'none' });
  });

  it('does not submit a dialog that is not open', () => {
    const { effect } = nextSaveState(initialSaveDialogState, 'submit');

    expect(effect).toBe('none');
  });

  it('settles back to the closed state after success or failure', () => {
    const pending: SaveDialogState = { open: true, pending: true };

    expect(nextSaveState(pending, 'settle')).toEqual({
      state: initialSaveDialogState,
      effect: 'none',
    });
  });
});
