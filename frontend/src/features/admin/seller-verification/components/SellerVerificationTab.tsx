import { useState } from 'react';
import { useSearchParams } from 'react-router-dom';
import { parsePositiveInt } from '../../../../lib/queryParams';
import type { SellerVerification } from '../api/useSellerVerifications';
import {
  useSellerVerificationCounts,
  useSellerVerifications,
} from '../api/useSellerVerifications';
import type { VerificationActionConfig, VerificationStatus } from './verificationModeration';
import { VERIFICATION_TABS, statusLabel, verificationActionsFor } from './verificationModeration';
import VerificationDetailsDialog from './VerificationDetailsDialog';
import VerificationReviewDialog from './VerificationReviewDialog';

function formatDate(dateString: string | null): string {
  if (!dateString) return '\u2014';
  const date = new Date(dateString);
  if (Number.isNaN(date.getTime())) return '\u2014';
  return date.toLocaleDateString('en-PH', {
    year: 'numeric',
    month: 'short',
    day: 'numeric',
  });
}

export function SellerVerificationTab() {
  const [activeStatus, setActiveStatus] = useState<VerificationStatus>('submitted');
  const [search, setSearch] = useState('');
  const [searchInput, setSearchInput] = useState('');
  const [page, setPage] = useState(1);
  const [detailsId, setDetailsId] = useState<number | null>(null);
  const [decision, setDecision] = useState<{
    verification: SellerVerification;
    action: VerificationActionConfig;
  } | null>(null);
  const [searchParams] = useSearchParams();
  const linkedVerificationId = parsePositiveInt(searchParams.get('verification'));
  const [dismissedLinkId, setDismissedLinkId] = useState<number | null>(null);

  const { data, isLoading, error, refetch } = useSellerVerifications({
    search: search || undefined,
    status: activeStatus,
    page,
    per_page: 15,
  });

  const { data: counts } = useSellerVerificationCounts();

  // The detail dialog fetches the record by id itself, so a deep link only has
  // to name the id; deriving it from the URL keeps the dialog in sync with the
  // address bar without an effect that copies the param into state.
  const activeDetailsId =
    detailsId ??
    (linkedVerificationId !== null && linkedVerificationId !== dismissedLinkId
      ? linkedVerificationId
      : null);

  const handleCloseDetails = () => {
    setDetailsId(null);
    if (linkedVerificationId !== null) setDismissedLinkId(linkedVerificationId);
  };

  const handleTabSelect = (status: VerificationStatus) => {
    setActiveStatus(status);
    setPage(1);
  };

  const handleSearch = () => {
    setSearch(searchInput);
    setPage(1);
  };

  const handleSearchKeyDown = (e: React.KeyboardEvent<HTMLInputElement>) => {
    if (e.key === 'Enter') {
      handleSearch();
    }
  };

  const handleRowKeyDown = (
    e: React.KeyboardEvent<HTMLTableRowElement>,
    verification: SellerVerification,
  ) => {
    // Only the row itself should open the details view: a keypress on one of the
    // action buttons inside it bubbles here too, and would otherwise open the
    // details dialog behind the review dialog.
    if (e.key === 'Enter' && e.target === e.currentTarget) {
      setDetailsId(verification.id);
    }
  };

  const verifications = data?.verifications ?? [];
  const pagination = data?.pagination;

  return (
    <div className="lv-tab-content verification-panel">
      <div className="lv-tabs" role="tablist" aria-label="Verification status">
        {VERIFICATION_TABS.map((tab) => {
          const isActive = tab.value === activeStatus;
          const count = counts?.[tab.value];

          return (
            <button
              key={tab.value}
              type="button"
              role="tab"
              aria-selected={isActive}
              className={`lv-tab${isActive ? ' lv-tab--active' : ''}`}
              onClick={() => handleTabSelect(tab.value)}
            >
              {tab.label}
              {count !== undefined && <span className="lv-tab-count">{count}</span>}
            </button>
          );
        })}
      </div>

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
        </div>
      </div>

      {isLoading ? (
        <div className="lv-loading">
          <div className="loading-spinner" />
          <span>Loading verification requests...</span>
        </div>
      ) : error ? (
        <div className="lv-error">
          <p className="lv-error-text">Failed to load verification requests.</p>
          <button type="button" className="lv-retry-button" onClick={() => refetch()}>
            Retry
          </button>
        </div>
      ) : verifications.length === 0 ? (
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
                {verifications.map((verification) => (
                  <tr
                    key={verification.id}
                    className="lv-listings-row"
                    tabIndex={0}
                    aria-label={`View details for ${verification.seller?.name ?? 'applicant'}`}
                    onClick={() => setDetailsId(verification.id)}
                    onKeyDown={(event) => handleRowKeyDown(event, verification)}
                  >
                    <td className="lv-name-cell">{verification.seller?.name ?? '\u2014'}</td>
                    <td>{verification.business_name}</td>
                    <td>{verification.business_location ?? '\u2014'}</td>
                    <td>
                      <span className={`lv-badge lv-badge--${verification.status}`}>
                        {statusLabel(verification.status)}
                      </span>
                    </td>
                    <td className="lv-date-cell">{formatDate(verification.submitted_at)}</td>
                    <td className="lv-date-cell">{formatDate(verification.reviewed_at)}</td>
                    <td>
                      <div
                        className="lv-action-buttons"
                        onClick={(event) => event.stopPropagation()}
                      >
                        {verificationActionsFor(verification.status).map((action) => (
                          <button
                            key={action.action}
                            type="button"
                            className={`lv-action-btn lv-action-btn--${action.variant}`}
                            onClick={() => setDecision({ verification, action })}
                          >
                            {action.label}
                          </button>
                        ))}
                      </div>
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
                onClick={() => setPage(pagination.current_page - 1)}
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
                onClick={() => setPage(pagination.current_page + 1)}
              >
                Next
              </button>
            </div>
          )}
        </>
      )}

      {decision && (
        <VerificationReviewDialog
          key={`${decision.verification.id}-${decision.action.action}`}
          verification={decision.verification}
          action={decision.action}
          onClose={() => setDecision(null)}
        />
      )}

      {activeDetailsId !== null && (
        <VerificationDetailsDialog
          verificationId={activeDetailsId}
          onClose={handleCloseDetails}
        />
      )}
    </div>
  );
}
