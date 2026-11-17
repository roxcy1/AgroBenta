import type { ReportDataset } from './api/exportReport';
import type { ReportParams } from './api/useReports';

function pad(value: number): string {
  return String(value).padStart(2, '0');
}

/**
 * Name the browser download for one exported dataset.
 *
 * The backend sets the same name on `Content-Disposition` for direct calls:
 * the Admin Web dev origin is cross-origin to the API, so the browser cannot
 * read that header and the file is named here instead.
 */
export function buildReportExportFilename(
  dataset: ReportDataset,
  params: ReportParams = {},
  now = new Date(),
): string {
  const range = params.date_from && params.date_to
    ? `${params.date_from}-to-${params.date_to}`
    : params.date_from
      ? `from-${params.date_from}`
      : params.date_to
        ? `through-${params.date_to}`
        : 'all-time';
  const timestamp = `${now.getFullYear()}${pad(now.getMonth() + 1)}${pad(now.getDate())}-${pad(now.getHours())}${pad(now.getMinutes())}${pad(now.getSeconds())}`;

  return `agrobenta-reports-${dataset}-${range}-${timestamp}.csv`;
}
