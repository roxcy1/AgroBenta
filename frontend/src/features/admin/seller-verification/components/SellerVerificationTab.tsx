import { useState } from 'react';
import {
  useSellerVerifications,
  useApproveVerification,
  useRejectVerification,
} from '../api/useSellerVerifications';

const STATUS_OPTIONS = [
  { value: '', label: 'All Statuses' },
  { value: 'submitted', label: 'Submitted' },
  { value: 'pending_review', label: 'Pending Review' },
  { value: 'approved', label: 'Approved' },
  { value: 'rejected', label: 'Rejected' },
] as const;

function formatDate(dateString: string | null): string {
  if (!dateString) return '—';
  const date = new Date(dateString);
  return date.toLocaleDateString('en-PH', {
    year: 'numeric',
    month: 'short',
    day: 'numeric',
  });
}

export function SellerVerificationTab() {
  const [search, setSearch] = useState('');
  const [statusFilter, setStatusFilter] = useState('');
  const [page, setPage] = useState(1);
  const [searchInput, setSearchInput] = useState('');
  const [actionNote, setActionNote] = useState('');
  const [actionTarget, setActionTarget] = useState<{ id: number; action: 'approve' | 'reject' } | null>(null);

  const { data, isLoading, error, refetch } = useSellerVerifications({
    search: search || undefined,
    status: statusFilter || undefined,
    page,
    per_page: 15,
  });

  const approveMutation = useApproveVerification();
  const rejectMutation = useRejectVerification();

  const handleSearch = () => {
    setSearch(searchInput);
    setPage(1);
  };

  const handleSearchKeyDown = (e: React.KeyboardEvent<HTMLInputElement>) => {
    if (e.key === 'Enter') {
      handleSearch();
    }
  };

  const handleStatusChange = (value: string) => {
    setStatusFilter(value);
    setPage(1);
  };

  const handlePageChange = (newPage: number) => {
    setPage(newPage);
  };

  const handleActionClick = (id: number, action: 'approve' | 'reject') => {
    setActionTarget({ id, action });
    setActionNote('');
  };

  const handleConfirmAction = () => {
    if (!actionTarget) return;

    if (actionTarget.action === 'approve') {
      approveMutation.mutate(
        { id: actionTarget.id, adminNote: actionNote || undefined },
        { onSettled: () => setActionTarget(null) },
      );
    } else {
      rejectMutation.mutate(
        { id: actionTarget.id, adminNote: actionNote || undefined },
        { onSettled: () => setActionTarget(null) },
      );
    }
  };

  const handleCancelAction = () => {
    setActionTarget(null);
    setActionNote('');
  };

  if (isLoading) {
    return (
      <div className="lv-loading">
        <div className="loading-spinner" />
        <span>Loading verification requests...</span>
      </div>
    );
  }

  if (error) {
    return (
      <div className="lv-error">
        <p className="lv-error-text">Failed to load verification requests.</p>
        <button type="button" className="lv-retry-button" onClick={() => refetch()}>
          Retry
        </button>
      </div>
    );
  }

  const verifications = data?.verifications ?? [];
  const pagination = data?.pagination;
  const isProcessing = approveMutation.isPending || rejectMutation.isPending;

  return (
    <div className="lv-tab-content">
      <div className="lv-controls">
        <div className="lv-search-row">
          <div className="lv-search-wrapper">
            <input
              type="text"
              className="lv-search-input"
              placeholder="Search by applicant name, email, or business..."
              value={searchInput}
              onChange={(e) => setSearchInput(e.target.value)}
              onKeyDown={handleSearchKeyDown}
            />
            <button type="button" className="lv-search-button" onClick={handleSearch}>
              Search
            </button>
          </div>

          <div className="lv-filters">
            <select
              className="lv-filter-select"
              value={statusFilter}
              onChange={(e) => handleStatusChange(e.target.value)}
            >
              {STATUS_OPTIONS.map((opt) => (
                <option key={opt.value} value={opt.value}>
                  {opt.label}
                </option>
              ))}
            </select>
          </div>
        </div>
      </div>

      {actionTarget && (
        <div className="lv-action-modal-overlay">
          <div className="lv-action-modal">
            <h3 className="lv-action-modal-title">
              {actionTarget.action === 'approve' ? 'Approve Verification' : 'Reject Verification'}
            </h3>
            <p className="lv-action-modal-desc">
              {actionTarget.action === 'approve'
                ? 'This will grant the applicant seller capability on the platform.'
                : 'This will reject the verification request. The applicant will remain a buyer.'}
            </p>
            <div className="lv-action-modal-field">
              <label className="lv-action-modal-label" htmlFor="admin-note">
                Admin Note (optional)
              </label>
              <textarea
                id="admin-note"
                className="lv-action-modal-textarea"
                rows={3}
                value={actionNote}
                onChange={(e) => setActionNote(e.target.value)}
                placeholder="Add a note for this decision..."
              />
            </div>
            <div className="lv-action-modal-buttons">
              <button
                type="button"
                className="lv-action-cancel"
                onClick={handleCancelAction}
                disabled={isProcessing}
              >
                Cancel
              </button>
              <button
                type="button"
                className={`lv-action-confirm lv-action-confirm--${actionTarget.action}`}
                onClick={handleConfirmAction}
                disabled={isProcessing}
              >
                {isProcessing
                  ? 'Processing...'
                  : actionTarget.action === 'approve'
                    ? 'Approve'
                    : 'Reject'}
              </button>
            </div>
          </div>
        </div>
      )}

      {verifications.length === 0 ? (
        <div className="lv-empty">
          <p>No seller verification requests found.</p>
        </div>
      ) : (
        <>
          <div className="lv-table-container">
            <table className="lv-table">
              <thead>
                <tr>
                  <th>Applicant</th>
                  <th>Business</th>
                  <th>Location</th>
                  <th>Status</th>
                  <th>Submitted</th>
                  <th>Reviewed</th>
                  <th>Actions</th>
                </tr>
              </thead>
              <tbody>
                {verifications.map((v) => (
                  <tr key={v.id}>
                    <td className="lv-name-cell">{v.seller.name}</td>
                    <td>{v.business_name}</td>
                    <td>{v.business_location ?? '—'}</td>
                    <td>
                      <span className={`lv-badge lv-badge--${v.status}`}>
                        {v.status === 'pending_review'
                          ? 'Pending Review'
                          : v.status.charAt(0).toUpperCase() + v.status.slice(1)}
                      </span>
                    </td>
                    <td className="lv-date-cell">{formatDate(v.submitted_at)}</td>
                    <td className="lv-date-cell">{formatDate(v.reviewed_at)}</td>
                    <td>
                      {(v.status === 'submitted' || v.status === 'pending_review') && (
                        <div className="lv-action-buttons">
                          <button
                            type="button"
                            className="lv-action-btn lv-action-btn--approve"
                            onClick={() => handleActionClick(v.id, 'approve')}
                            disabled={isProcessing}
                          >
                            Approve
                          </button>
                          <button
                            type="button"
                            className="lv-action-btn lv-action-btn--reject"
                            onClick={() => handleActionClick(v.id, 'reject')}
                            disabled={isProcessing}
                          >
                            Reject
                          </button>
                        </div>
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>

          {pagination && pagination.last_page > 1 && (
            <div className="lv-pagination">
              <button
                type="button"
                className="lv-page-button"
                disabled={pagination.current_page <= 1}
                onClick={() => handlePageChange(pagination.current_page - 1)}
              >
                Previous
              </button>
              <span className="lv-page-info">
                Page {pagination.current_page} of {pagination.last_page}
                {' '}
                <span className="lv-page-total">({pagination.total} requests)</span>
              </span>
              <button
                type="button"
                className="lv-page-button"
                disabled={pagination.current_page >= pagination.last_page}
                onClick={() => handlePageChange(pagination.current_page + 1)}
              >
                Next
              </button>
            </div>
          )}
        </>
      )}
    </div>
  );
}
