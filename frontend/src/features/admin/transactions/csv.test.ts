import { describe, expect, it } from 'vitest';
import { buildTransactionsCsv, buildTransactionsFilename, escapeCsvField } from './csv';
import type { Transaction } from './api/useTransactions';

function makeTransaction(overrides: Partial<Transaction> = {}): Transaction {
  return {
    id: 1,
    buyer: { id: 10, name: 'Juan Dela Cruz', email: 'juan@example.com' },
    seller: { id: 20, name: 'Maria Santos', email: 'maria@example.com' },
    listing: { id: 30, livestock_type: 'Cattle', breed: 'Brahman' },
    quantity: 3,
    total_amount: '50000.00',
    status: 'completed',
    created_at: '2026-10-01T08:30:00.000000Z',
    updated_at: '2026-10-02T09:00:00.000000Z',
    ...overrides,
  };
}

describe('escapeCsvField', () => {
  it('leaves a value without special characters untouched', () => {
    expect(escapeCsvField('Brahman')).toBe('Brahman');
  });

  it('quotes a value containing a comma', () => {
    expect(escapeCsvField('Dela Cruz, Juan')).toBe('"Dela Cruz, Juan"');
  });

  it('quotes and doubles a value containing a double quote', () => {
    expect(escapeCsvField('He said "hi"')).toBe('"He said ""hi"""');
  });

  it('quotes a value containing a line break', () => {
    expect(escapeCsvField('line one\nline two')).toBe('"line one\nline two"');
    expect(escapeCsvField('line one\r\nline two')).toBe('"line one\r\nline two"');
  });

  it('renders null and undefined as an empty field', () => {
    expect(escapeCsvField(null)).toBe('');
    expect(escapeCsvField(undefined)).toBe('');
  });
});

describe('buildTransactionsCsv', () => {
  it('writes a header row followed by one row per transaction', () => {
    const csv = buildTransactionsCsv([makeTransaction(), makeTransaction({ id: 2 })]);

    expect(csv.split('\r\n')).toHaveLength(3);
    expect(csv.split('\r\n')[0]).toBe(
      'Transaction ID,Buyer Name,Buyer Email,Seller Name,Seller Email,Livestock Type,Breed,Quantity,Total Amount,Status,Created At',
    );
  });

  it('exports the exact amount string with no currency symbol or re-rounding', () => {
    const csv = buildTransactionsCsv([makeTransaction({ total_amount: '50000.00' })]);
    const row = csv.split('\r\n')[1];

    expect(row).toContain(',50000.00,');
    expect(row).not.toContain('\u20B1');
    expect(row).not.toContain('50,000.00');
  });

  it('escapes commas, quotes, and line breaks in text fields', () => {
    const csv = buildTransactionsCsv([
      makeTransaction({
        buyer: { id: 10, name: 'Dela Cruz, "Juan"', email: 'juan@example.com' },
        listing: { id: 30, livestock_type: 'Cattle\nDairy', breed: 'Brahman' },
      }),
    ]);
    const row = csv.split('\r\n').slice(1).join('\r\n');

    expect(row).toContain('"Dela Cruz, ""Juan"""');
    expect(row).toContain('"Cattle\nDairy"');
  });

  it('writes empty fields when optional parts of a transaction are missing', () => {
    const transaction = makeTransaction();
    const csv = buildTransactionsCsv([
      {
        ...transaction,
        buyer: { id: 10, name: '', email: '' },
        listing: { id: 30, livestock_type: '', breed: '' },
      },
    ]);

    expect(csv.split('\r\n')[1]).toBe('1,,,Maria Santos,maria@example.com,,,3,50000.00,completed,2026-10-01T08:30:00.000000Z');
  });
});

describe('buildTransactionsFilename', () => {
  it('names the file with a sortable timestamp and csv extension', () => {
    const filename = buildTransactionsFilename(new Date(2026, 9, 12, 6, 5, 9));

    expect(filename).toBe('transactions-20261012-060509.csv');
    expect(filename).toMatch(/^transactions-\d{8}-\d{6}\.csv$/);
  });
});
