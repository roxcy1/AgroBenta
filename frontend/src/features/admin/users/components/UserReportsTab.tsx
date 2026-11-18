import { useState } from 'react';
import { Eye } from 'lucide-react';
import type { UserReportStatus } from '../api/useUserReports';
import { useUserReports } from '../api/useUserReports';
import { PAGE_ELLIPSIS, buildPageWindow } from '../pagination';
import { StatusBadge } from '../../components/StatusBadge';
import { formatDate } from '../../../../lib/format';
import { emptyListMessage } from '../../../../lib/emptyState';
import UserReportReviewDialog from './UserReportReviewDialog';

const ROWS_PER_PAGE_OPTIONS = [10, 15, 25, 50, 100] as const;

const STATUS_OPTIONS: Array<{ value: '' | UserReportStatus; label: string }> = [
  { value: '', label: 'All Reports' },
  { value: 'pending', label: 'Pending' },
  { value: 'dismissed', label: 'Dismissed' },
  { value: 'actioned', label: 'Actioned' },
];

export default function UserReportsTab() {
  const [statusFilter, setStatusFilter] = useState<'' | UserReportStatus>('');
  const [page, setPage] = useState(1);
  const [perPage, setPerPage] = useState(15);
  const [reviewId, setReviewId] = useState<number | null>(null);

  const { data, isLoading, isFetching, error, refetch } = useUserReports({
    status: statusFilter || undefined,
    page,
    per_page: perPage,
  });

  const reports = data?.reports ?? [];
  const pagination = data?.pagination;
  const resultStart = pagination && pagination.total > 0
    ? (pagination.current_page - 1) * pagination.per_page + 1
    : 0;
  const resultEnd = pagination && pagination.total > 0
    ? Math.min((pagination.current_page - 1) * pagination.per_page + reports.length, pagination.total)
    : 0;

  const handleStatusChange = (value: string) => {
    setStatusFilter(value as '' | UserReportStatus);
    setPage(1);
  };

  const handlePageChange = (nextPage: number) => {
    if (isFetching) return;
    const lastPage = pagination?.last_page ?? 1;
    if (nextPage < 1 || nextPage > lastPage || nextPage === page) return;
    setPage(nextPage);
  };

  const handlePerPageChange = (value: string) => {
    const nextPerPage = Number(value);
    if (!ROWS_PER_PAGE_OPTIONS.includes(nextPerPage as (typeof ROWS_PER_PAGE_OPTIONS)[number])) return;
    setPerPage(nextPerPage);
    setPage(1);
  };

  return (
    <div className="user-reports-panel">
      <div className="users-controls lv-controls">
        <div className="users-search-row lv-search-row">
          <div className="users-filters lv-filters">
            <select
              className="users-filter-select lv-filter-select"
              aria-label="Filter reports by status"
              value={statusFilter}
              onChange={(event) => handleStatusChange(event.target.value)}
            >
              {STATUS_OPTIONS.map((option) => (
                <option key={option.value} value={option.value}>
                  {option.label}
                </option>
              ))}
            </select>
          </div>
        </div>
      </div>

      {isLoading ? (
        <div className="users-loading">
          <div className="loading-spinner" />
          <span>Loading reports...</span>
        </div>
      ) : error ? (
        <div className="users-error">
          <p className="users-error-text">Failed to load reports.</p>
          <button type="button" className="users-retry-button" onClick={() => refetch()}>
            Retry
          </button>
        </div>
      ) : reports.length === 0 ? (
        <div className="users-empty">
          <p>{emptyListMessage('reports', Boolean(statusFilter))}</p>
        </div>
      ) : (
        <>
          <div
            className={`users-table-container lv-table-container${isFetching ? ' users-table-container--fetching' : ''}`}
            aria-busy={isFetching}
          >
            <table className="users-table lv-table user-reports-table">
              <thead>
                <tr>
                  <th>Reporter</th>
                  <th>Reported User</th>
                  <th>Reason</th>
                  <th>Date</th>
                  <th>Status</th>
                  <th className="users-actions-heading">Action</th>
                </tr>
              </thead>
              <tbody>
                {reports.map((report) => (
                  <tr key={report.id} className="user-reports-row">
                    <td className="users-name-cell" data-label="Reporter">
                      {report.reporter?.name ?? '\u2014'}
                    </td>
                    <td className="users-name-cell" data-label="Reported User">
                      {report.reported_user?.name ?? '\u2014'}
                    </td>
                    <td data-label="Reason">{report.reason_label}</td>
                    <td className="users-date-cell" data-label="Date">
                      {formatDate(report.created_at)}
                    </td>
                    <td data-label="Status">
                      <StatusBadge status={report.status} />
                    </td>
                    <td className="users-actions-cell" data-label="Action">
                      <button
                        type="button"
                        className="user-reports-review-button"
                        onClick={() => setReviewId(report.id)}
                        aria-label={`Review report ${report.id}`}
                      >
                        <Eye size={15} aria-hidden="true" />
                        <span>Review</span>
                      </button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>

          {pagination && (
            <nav className="users-pagination" aria-label="User reports pagination">
              <span className="users-page-info" aria-live="polite">
                Showing {resultStart}–{resultEnd} of {pagination.total} reports
                {isFetching && <span className="users-page-updating"> · Updating…</span>}
              </span>
              <div className="users-pagination-actions">
                <label className="users-rows-per-page">
                  <span>Rows per page:</span>
                  <select
                    aria-label="Rows per page"
                    value={perPage}
                    onChange={(event) => handlePerPageChange(event.target.value)}
                  >
                    {ROWS_PER_PAGE_OPTIONS.map((value) => (
                      <option key={value} value={value}>{value}</option>
                    ))}
                  </select>
                </label>
                <div className="users-pagination-buttons">
                  <button
                    type="button"
                    className="users-page-button"
                    disabled={isFetching || pagination.current_page <= 1}
                    onClick={() => handlePageChange(pagination.current_page - 1)}
                    aria-label="Go to previous page"
                  >
                    Previous
                  </button>

                  {pagination.last_page > 1 && buildPageWindow(
                    pagination.current_page,
                    pagination.last_page,
                  ).map((item, index) =>
                    item === PAGE_ELLIPSIS ? (
                      <span
                        key={`ellipsis-${index}`}
                        className="users-page-ellipsis"
                        aria-hidden="true"
                      >
                        &hellip;
                      </span>
                    ) : (
                      <button
                        key={item}
                        type="button"
                        className={`users-page-number${
                          item === pagination.current_page ? ' users-page-number--active' : ''
                        }`}
                        disabled={isFetching}
                        aria-label={`Go to page ${item}`}
                        aria-current={item === pagination.current_page ? 'page' : undefined}
                        onClick={() => handlePageChange(item)}
                      >
                        {item}
                      </button>
                    ),
                  )}

                  <button
                    type="button"
                    className="users-page-button"
                    disabled={isFetching || pagination.current_page >= pagination.last_page}
                    onClick={() => handlePageChange(pagination.current_page + 1)}
                    aria-label="Go to next page"
                  >
                    Next
                  </button>
                </div>
              </div>
            </nav>
          )}
        </>
      )}

      {reviewId !== null && (
        <UserReportReviewDialog reportId={reviewId} onClose={() => setReviewId(null)} />
      )}
    </div>
  );
}
