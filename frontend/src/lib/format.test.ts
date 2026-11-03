import { describe, expect, it } from 'vitest';
import { formatDate, formatDateTime, formatNumber, formatPeso } from './format';

describe('formatPeso', () => {
  it('groups a decimal string and keeps two decimals', () => {
    expect(formatPeso('42500.00')).toBe('₱42,500.00');
    expect(formatPeso('1234567.5')).toBe('₱1,234,567.50');
    expect(formatPeso('0')).toBe('₱0.00');
  });

  it('formats a number the same way', () => {
    expect(formatPeso(42500)).toBe('₱42,500.00');
    expect(formatPeso(0)).toBe('₱0.00');
  });

  it('never rounds the exact amount the server sent', () => {
    // 17 significant digits: a float would round the last digits away.
    expect(formatPeso('12345678901234.99')).toBe('₱12,345,678,901,234.99');
  });

  it('shows a dash, not zero, when there is no amount', () => {
    expect(formatPeso(null)).toBe('—');
    expect(formatPeso(undefined)).toBe('—');
    expect(formatPeso('')).toBe('—');
    expect(formatPeso('abc')).toBe('—');
  });
});

describe('formatDate and formatDateTime', () => {
  const iso = '2026-11-02T12:00:00Z';

  it('formats a date with the year', () => {
    expect(formatDate(iso)).toMatch(/^Nov 2, 2026$/);
  });

  it('adds the time for detail views', () => {
    expect(formatDateTime(iso)).toMatch(/^Nov 2, 2026, \d{1,2}:\d{2}\s?[AP]M$/i);
  });

  it('shows a dash for a missing or invalid date', () => {
    expect(formatDate(null)).toBe('—');
    expect(formatDate('not a date')).toBe('—');
    expect(formatDateTime(undefined)).toBe('—');
  });
});

describe('formatNumber', () => {
  it('adds thousands separators', () => {
    expect(formatNumber(1250)).toBe('1,250');
  });
});
