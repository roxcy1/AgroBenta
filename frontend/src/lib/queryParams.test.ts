import { describe, expect, it } from 'vitest';
import { parsePositiveInt, resolveDeepLinkedRecord } from './queryParams';

describe('parsePositiveInt', () => {
  it('returns the number for a positive integer string', () => {
    expect(parsePositiveInt('42')).toBe(42);
  });

  it('returns null for null, undefined and empty input', () => {
    expect(parsePositiveInt(null)).toBeNull();
    expect(parsePositiveInt(undefined)).toBeNull();
    expect(parsePositiveInt('')).toBeNull();
    expect(parsePositiveInt('   ')).toBeNull();
  });

  it('returns null for zero and negative values', () => {
    expect(parsePositiveInt('0')).toBeNull();
    expect(parsePositiveInt('-3')).toBeNull();
  });

  it('returns null for non-numeric and decimal input', () => {
    expect(parsePositiveInt('abc')).toBeNull();
    expect(parsePositiveInt('1.5')).toBeNull();
    expect(parsePositiveInt('12abc')).toBeNull();
    expect(parsePositiveInt('NaN')).toBeNull();
  });

  it('accepts surrounding whitespace around a valid integer', () => {
    expect(parsePositiveInt(' 7 ')).toBe(7);
  });
});

describe('resolveDeepLinkedRecord', () => {
  const link = (overrides: Partial<Parameters<typeof resolveDeepLinkedRecord>[0]> = {}) =>
    resolveDeepLinkedRecord({
      entity: 'Listing',
      id: 5,
      dismissedId: null,
      record: undefined,
      isError: false,
      ...overrides,
    });

  it('is inactive when no id is present', () => {
    expect(link({ id: null })).toEqual({ record: null, status: 'inactive', message: null });
  });

  it('is inactive once the link has been dismissed', () => {
    const state = link({ dismissedId: 5, record: { id: 5 } });

    expect(state).toEqual({ record: null, status: 'inactive', message: null });
  });

  it('is loading while the record query has not settled', () => {
    expect(link()).toEqual({ record: null, status: 'loading', message: null });
  });

  it('is missing when the query failed and reports it', () => {
    const state = link({ isError: true });

    expect(state.status).toBe('missing');
    expect(state.record).toBeNull();
    expect(state.message).toBe('Listing #5 could not be loaded. It may have been removed.');
  });

  it('names the linked entity in the missing message', () => {
    expect(link({ entity: 'Transaction', id: 12, isError: true }).message).toBe(
      'Transaction #12 could not be loaded. It may have been removed.',
    );
    expect(link({ entity: 'User', id: 7, isError: true }).message).toBe(
      'User #7 could not be loaded. It may have been removed.',
    );
  });

  it('is ready with the fetched record', () => {
    const state = link({ record: { id: 5 } });

    expect(state).toEqual({ record: { id: 5 }, status: 'ready', message: null });
  });

  it('prefers a fetched record over a later failed refresh', () => {
    const state = link({ record: { id: 5 }, isError: true });

    expect(state.status).toBe('ready');
    expect(state.record).toEqual({ id: 5 });
  });
});
