import { useState } from 'react';
import { useInquiries } from '../api/useInquiries';
import type { Inquiry } from '../api/useInquiries';
import {
  INQUIRY_STATUS_FILTER_OPTIONS,
  statusBadgeClass,
  statusLabel,
} from './inquiryModeration';
import InquiryDetailsDialog from './InquiryDetailsDialog';

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

function listingLabel(inquiry: Inquiry): string {
  if (!inquiry.listing) return '\u2014';
  return `${inquiry.listing.livestock_type} / ${inquiry.listing.breed}`;
}

/**
 * The inquiry inbox.
 *
 * A read-and-work view: the administrator filters, opens one, and changes its
 * status or deletes it. Inquiries are created by buyers elsewhere, so there is
 * no "new" action here. The detail dialog fetches the record by id itself, so
 * the list only has to hand over the id.
 */
export function InquiriesPage() {
  const [searchInput, setSearchInput] = useState('');
  const [search, setSearch] = useState('');
  const [statusFilter, setStatusFilter] = useState('');
  const [page, setPage] = useState(1);
  const [detailsId, setDetailsId] = useState<number | null>(null);

  const { data, isLoading, error, refetch } = useInquiries({
    search: search || undefined,
    status: statusFilter || undefined,
    page,
    per_page: 15,
  });

  const inquiries = data?.inquiries ?? [];
  const pagination = data?.pagination;

  const handleSearch = () => {
    setSearch(searchInput);
    setPage(1);
  };

  const handleSearchKeyDown = (event: React.KeyboardEvent<HTMLInputElement>) => {
    if (event.key === 'Enter') {
      handleSearch();
    }
  };

  const handleStatusChange = (value: string) => {
    setStatusFilter(value);
    setPage(1);
  };

  return (
    <div className="lv-tab-content">
      {isLoading ? (
        <div className="lv-loading">
          <div className="loading-spinner" />
          <span>Loading inquiries...</span>
        </div>
      ) : error ? (
        <div className="lv-error">
          <p className="lv-error-text">Failed to load inquiries.</p>
          <button type="button" className="lv-retry-button" onClick={() => refetch()}>
            Retry
          </button>
        </div>
      ) : (
        <>
          <div className="lv-controls">
            <div className="lv-search-row">
              <div className="lv-search-wrapper">
                <input
                  type="text"
                  className="lv-search-input"
                  placeholder="Search by ID, buyer, seller, or subject..."
                  value={searchInput}
                  onChange={(event) => setSearchInput(event.target.value)}
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
                  onChange={(event) => handleStatusChange(event.target.value)}
                >
                  {INQUIRY_STATUS_FILTER_OPTIONS.map((option) => (
                    <option key={option.value} value={option.value}>
                      {option.label}
                    </option>
                  ))}
                </select>
              </div>
            </div>
          </div>

          {inquiries.length === 0 ? (
            <div className="lv-empty">
              <p>No inquiries found.</p>
            </div>
          ) : (
            <>
              <div className="lv-table-container">
                <table className="lv-table">
                  <thead>
                    <tr>
                      <th>Inquiry ID</th>
                      <th>Buyer</th>
                      <th>Seller</th>
                      <th>Listing</th>
                      <th>Subject</th>
                      <th>Status</th>
                      <th>Received</th>
                      <th>Actions</th>
                    </tr>
                  </thead>
                  <tbody>
                    {inquiries.map((inquiry) => (
                      <tr key={inquiry.id}>
                        <td className="lv-name-cell">#{inquiry.id}</td>
                        <td className="lv-seller-cell">{inquiry.buyer?.name ?? '\u2014'}</td>
                        <td className="lv-seller-cell">{inquiry.seller?.name ?? '\u2014'}</td>
                        <td>{listingLabel(inquiry)}</td>
                        <td>{inquiry.subject || '\u2014'}</td>
                        <td>
                          <span className={statusBadgeClass(inquiry.status)}>
                            {statusLabel(inquiry.status)}
                          </span>
                        </td>
                        <td className="lv-date-cell">{formatDate(inquiry.created_at)}</td>
                        <td>
                          <div className="lv-action-buttons">
                            <button
                              type="button"
                              className="lv-action-btn lv-action-btn--view"
                              onClick={() => setDetailsId(inquiry.id)}
                            >
                              View
                            </button>
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
                    <span className="lv-page-total">({pagination.total} inquiries)</span>
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
        </>
      )}

      {detailsId !== null && (
        <InquiryDetailsDialog inquiryId={detailsId} onClose={() => setDetailsId(null)} />
      )}
    </div>
  );
}
