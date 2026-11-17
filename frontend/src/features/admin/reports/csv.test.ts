import { describe, expect, it } from 'vitest';
import { buildReportExportFilename } from './csv';

describe('buildReportExportFilename', () => {
  it('names the file after the dataset, the selected range and a sortable timestamp', () => {
    const filename = buildReportExportFilename(
      'transactions',
      { date_from: '2026-01-01', date_to: '2026-01-31' },
      new Date(2026, 0, 12, 6, 5, 9),
    );

    expect(filename).toBe('agrobenta-reports-transactions-2026-01-01-to-2026-01-31-20260112-060509.csv');
  });

  it('uses an all-time label when no range is applied', () => {
    expect(buildReportExportFilename('users', {}, new Date(2026, 0, 12, 6, 5, 9)))
      .toBe('agrobenta-reports-users-all-time-20260112-060509.csv');
  });

  it('handles open-ended ranges', () => {
    const now = new Date(2026, 0, 12, 6, 5, 9);

    expect(buildReportExportFilename('listings', { date_from: '2026-01-01' }, now))
      .toBe('agrobenta-reports-listings-from-2026-01-01-20260112-060509.csv');
    expect(buildReportExportFilename('seller-verifications', { date_to: '2026-01-31' }, now))
      .toBe('agrobenta-reports-seller-verifications-through-2026-01-31-20260112-060509.csv');
  });
});
