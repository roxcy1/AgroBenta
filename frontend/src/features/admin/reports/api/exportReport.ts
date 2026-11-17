import api from '../../../../lib/api';
import type { ReportParams } from './useReports';

/**
 * The record datasets the Reports page can download.
 *
 * The values are the backend route's dataset names. The labels are what the
 * export selector shows; both lists must match `AdminReportExportService`'s
 * registry.
 */
export type ReportDataset =
  | 'transactions'
  | 'listings'
  | 'users'
  | 'seller-verifications'
  | 'activities';

export const REPORT_DATASETS: ReadonlyArray<{ value: ReportDataset; label: string }> = [
  { value: 'transactions', label: 'Transactions' },
  { value: 'listings', label: 'Listings' },
  { value: 'users', label: 'Users' },
  { value: 'seller-verifications', label: 'Seller verifications' },
  { value: 'activities', label: 'Activities' },
];

/**
 * Download one dataset's records for the applied date range.
 *
 * The API responds with CSV bytes (one row per stored record created in the
 * range), so the response is read as a blob rather than JSON.
 */
export async function fetchReportExport(
  dataset: ReportDataset,
  params: ReportParams = {},
): Promise<Blob> {
  const query = new URLSearchParams();
  if (params.date_from) query.set('date_from', params.date_from);
  if (params.date_to) query.set('date_to', params.date_to);

  const qs = query.toString();
  const url = `/admin/reports/export/${dataset}${qs ? `?${qs}` : ''}`;

  const response = await api.get<Blob>(url, { responseType: 'blob' });
  return response.data;
}
