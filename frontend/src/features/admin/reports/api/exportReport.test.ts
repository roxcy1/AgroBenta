import { afterEach, describe, expect, it, vi } from 'vitest';
import type { AxiosResponse } from 'axios';
import api from '../../../../lib/api';
import { fetchReportExport, REPORT_DATASETS } from './exportReport';

describe('REPORT_DATASETS', () => {
  it('offers every record dataset the reports page can export', () => {
    expect(REPORT_DATASETS.map((dataset) => dataset.value)).toEqual([
      'transactions',
      'listings',
      'users',
      'seller-verifications',
      'activities',
    ]);
  });
});

describe('fetchReportExport', () => {
  afterEach(() => {
    vi.restoreAllMocks();
  });

  it('requests the selected dataset as a CSV blob with the applied range', async () => {
    const blob = new Blob(['a,b'], { type: 'text/csv' });
    const spy = vi.spyOn(api, 'get').mockResolvedValue({ data: blob } as AxiosResponse);

    const result = await fetchReportExport('transactions', {
      date_from: '2026-01-01',
      date_to: '2026-01-31',
    });

    expect(spy).toHaveBeenCalledWith(
      '/admin/reports/export/transactions?date_from=2026-01-01&date_to=2026-01-31',
      { responseType: 'blob' },
    );
    expect(result).toBe(blob);
  });

  it('omits dates that are not applied', async () => {
    const spy = vi.spyOn(api, 'get').mockResolvedValue({ data: new Blob([]) } as AxiosResponse);

    await fetchReportExport('users');

    expect(spy).toHaveBeenCalledWith('/admin/reports/export/users', { responseType: 'blob' });
  });
});
