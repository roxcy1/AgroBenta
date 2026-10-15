import { describe, expect, it } from 'vitest';
import {
  settingsErrorMessage,
  settingsRejectedMessage,
  settingsSuccessMessage,
} from './settingsErrorMessage';

describe('settingsErrorMessage', () => {
  it('maps 403 to a permission message', () => {
    expect(settingsErrorMessage({ response: { status: 403 } })).toBe(
      'You do not have permission to change settings.',
    );
  });

  it('maps 422 to a validation message', () => {
    expect(settingsErrorMessage({ response: { status: 422 } })).toBe(
      'The settings were rejected as invalid. Review the form and try again.',
    );
  });

  it('maps 500 to a server message', () => {
    expect(settingsErrorMessage({ response: { status: 500 } })).toBe(
      'The server could not save the settings. Please try again.',
    );
  });

  it('falls back to a generic connection message', () => {
    expect(settingsErrorMessage(new Error('network'))).toBe(
      'The settings could not be saved. Check your connection and try again.',
    );
    expect(settingsErrorMessage(undefined)).toBe(
      'The settings could not be saved. Check your connection and try again.',
    );
  });
});

describe('settingsSuccessMessage', () => {
  it('singularises one setting', () => {
    expect(settingsSuccessMessage(['system.name'])).toBe('Saved 1 setting.');
  });

  it('pluralises several settings', () => {
    expect(settingsSuccessMessage(['system.name', 'listing.max_photos'])).toBe('Saved 2 settings.');
  });
});

describe('settingsRejectedMessage', () => {
  it('names the rejected keys', () => {
    expect(settingsRejectedMessage(['nope.key'])).toBe(
      'The server did not recognise setting: nope.key.',
    );
    expect(settingsRejectedMessage(['a', 'b'])).toBe(
      'The server did not recognise settings: a, b.',
    );
  });
});
