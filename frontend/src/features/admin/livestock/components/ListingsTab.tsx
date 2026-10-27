import { useState } from 'react';
import { useSearchParams } from 'react-router-dom';
import { parsePositiveInt, resolveDeepLinkedRecord } from '../../../../lib/queryParams';
import { useListing, useListingCounts, useListings } from '../api/useListings';
import type { Listing } from '../api/useListings';
import ListingDetailsDialog from './ListingDetailsDialog';
import ListingReviewDialog from './ListingReviewDialog';
import ListingStatsCards from './ListingStatsCards';
import type { ModerationOption } from './listingModeration';
import { moderationOptionsFor, statusLabel } from './listingModeration';

const STATUS_OPTIONS = [
  { value: '', label: 'All Statuses' },
  { value: 'draft', label: 'Draft' },
  { value: 'pending', label: 'Pending' },
  { value: 'active', label: 'Active' },
  { value: 'sold', label: 'Sold' },
  { value: 'inactive', label: 'Inactive' },
] as const;

const LIVESTOCK_OPTIONS = [
  { value: '', label: 'All Types' },
  { value: 'cattle', label: 'Cattle' },
  { value: 'carabao', label: 'Carabao' },
  { value: 'goat', label: 'Goat' },
  { value: 'pig', label: 'Pig' },
  { value: 'chicken', label: 'Chicken' },
  { value: 'duck', label: 'Duck' },
  { value: 'horse', label: 'Horse' },
  { value: 'sheep', label: 'Sheep' },
] as const;

function formatCurrency(value: string): string {
  const num = parseFloat(value);
  if (isNaN(num)) return '₱0';
  return `₱${num.toLocaleString('en-PH', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;
}

function formatDate(dateString: string): string {
  const date = new Date(dateString);
  return date.toLocaleDateString('en-PH', {
    year: 'numeric',
    month: 'short',
    day: 'numeric',
  });
}

export function ListingsTab() {
  const [search, setSearch] = useState('');
  const [statusFilter, setStatusFilter] = useState('');
  const [typeFilter, setTypeFilter] = useState('');
  const [page, setPage] = useState(1);
  const [searchInput, setSearchInput] = useState('');
  const [details, setDetails] = useState<Listing | null>(null);
  const [decision, setDecision] = useState<{
    listing: Listing;
    option: ModerationOption;
  } | null>(null);
  const [searchParams] = useSearchParams();
  const linkedListingId = parsePositiveInt(searchParams.get('listing'));
  const [dismissedLinkId, setDismissedLinkId] = useState<number | null>(null);

  const { data, isLoading, error, refetch } = useListings({
    search: search || undefined,
    status: statusFilter || undefined,
    livestock_type: typeFilter || undefined,
    page,
    per_page: 15,
  });

  const { data: counts } = useListingCounts();
  const { data: linkedListing, isError: linkedListingFailed } = useListing(linkedListingId);

  // A deep link opens the listing it names even when that row is not on the
  // page the list is showing. Deriving the dialog's record from the query
  // result rather than syncing it into state keeps the URL the single source
  // of truth for the open dialog.
  const linkedState = resolveDeepLinkedRecord({
    entity: 'Listing',
    id: linkedListingId,
    dismissedId: dismissedLinkId,
    record: linkedListing,
    isError: linkedListingFailed,
  });
  const activeDetails = details ?? linkedState.record;

  const handleCloseDetails = () => {
    setDetails(null);
    if (linkedListingId !== null) setDismissedLinkId(linkedListingId);
  };

  const handleDismissLinkedNotice = () => {
    if (linkedListingId !== null) setDismissedLinkId(linkedListingId);
  };

  const handleStatusCardSelect = (status: string) => {
    setStatusFilter((current) => (current === status ? '' : status));
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
    listing: Listing,
  ) => {
    if (e.target !== e.currentTarget) return;
    if (e.key === 'Enter' || e.key === ' ') {
      e.preventDefault();
      setDetails(listing);
    }
  };

  const handleStatusChange = (value: string) => {
    setStatusFilter(value);
    setPage(1);
  };

  const handleTypeChange = (value: string) => {
    setTypeFilter(value);
    setPage(1);
  };

  const handlePageChange = (newPage: number) => {
    setPage(newPage);
  };

  const listings = data?.listings ?? [];
  const pagination = data?.pagination;

  return (
    <>
      <div className="lv-tab-content">
        <ListingStatsCards
          counts={counts}
          activeStatus={statusFilter}
          onSelect={handleStatusCardSelect}
        />

        {isLoading ? (
          <div className="lv-loading">
            <div className="loading-spinner" />
            <span>Loading listings...</span>
          </div>
        ) : error ? (
          <div className="lv-error">
            <p className="lv-error-text">Failed to load listings.</p>
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
                    placeholder="Search by type, breed, or location..."
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
                    value={typeFilter}
                    onChange={(e) => handleTypeChange(e.target.value)}
                  >
                    {LIVESTOCK_OPTIONS.map((opt) => (
                      <option key={opt.value} value={opt.value}>
                        {opt.label}
                      </option>
                    ))}
                  </select>

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

            {linkedState.message !== null && (
              <div className="deep-link-notice" role="alert">
                <p className="deep-link-notice-text">{linkedState.message}</p>
                <button
                  type="button"
                  className="deep-link-notice-dismiss"
                  onClick={handleDismissLinkedNotice}
                >
                  Dismiss
                </button>
              </div>
            )}

            {listings.length === 0 ? (
              <div className="lv-empty">
                <p>No livestock listings found.</p>
              </div>
            ) : (
              <>
                <div className="lv-table-container">
                  <table className="lv-table">
                    <thead>
                      <tr>
                        <th>Type</th>
                        <th>Breed</th>
                        <th>Qty</th>
                        <th>Price</th>
                        <th>Location</th>
                        <th>Seller</th>
                        <th>Status</th>
                        <th>Date</th>
                        <th>Actions</th>
                      </tr>
                    </thead>
                    <tbody>
                      {listings.map((listing) => (
                        <tr
                          key={listing.id}
                          className="lv-listings-row"
                          tabIndex={0}
                          aria-label={`View details for ${listing.livestock_type} listing`}
                          onClick={() => setDetails(listing)}
                          onKeyDown={(event) => handleRowKeyDown(event, listing)}
                        >
                          <td className="lv-name-cell">{listing.livestock_type}</td>
                          <td>{listing.breed}</td>
                          <td>{listing.quantity}</td>
                          <td className="lv-price-cell">{formatCurrency(listing.asking_price)}</td>
                          <td>{listing.location}</td>
                          <td className="lv-seller-cell">{listing.seller.name}</td>
                          <td>
                            <span className={`lv-badge lv-badge--${listing.status}`}>
                              {statusLabel(listing.status)}
                            </span>
                          </td>
                          <td>{formatDate(listing.created_at)}</td>
                          <td>
                            <div
                              className="lv-action-buttons"
                              onClick={(event) => event.stopPropagation()}
                            >
                              {moderationOptionsFor(listing.status).map((option) => (
                                <button
                                  key={option.action}
                                  type="button"
                                  className={`lv-action-btn lv-action-btn--${option.variant}`}
                                  onClick={() => setDecision({ listing, option })}
                                >
                                  {option.label}
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
                      onClick={() => handlePageChange(pagination.current_page - 1)}
                    >
                      Previous
                    </button>
                    <span className="lv-page-info">
                      Page {pagination.current_page} of {pagination.last_page}
                      {' '}
                      <span className="lv-page-total">
                        ({pagination.total} listings)
                      </span>
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
          </>
        )}
      </div>

      {decision && (
        <ListingReviewDialog
          // Remounting per decision is what resets the note and any error: the
          // dialog holds them as state, and a fresh key is cheaper and less
          // error-prone than an effect that clears them after the fact.
          key={`${decision.listing.id}-${decision.option.action}`}
          listing={decision.listing}
          option={decision.option}
          onClose={() => setDecision(null)}
        />
      )}

      {activeDetails && (
        <ListingDetailsDialog listing={activeDetails} onClose={handleCloseDetails} />
      )}
    </>
  );
}
