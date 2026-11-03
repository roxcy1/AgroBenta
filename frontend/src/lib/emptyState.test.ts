import { describe, expect, it } from 'vitest';
import { emptyListMessage } from './emptyState';

describe('emptyListMessage', () => {
  it('says nothing exists yet when no filter is applied', () => {
    expect(emptyListMessage('transactions', false)).toBe('No transactions available yet.');
  });

  it('says nothing matches when a filter is applied', () => {
    expect(emptyListMessage('users', true)).toBe('No users match the current filters.');
  });
});
