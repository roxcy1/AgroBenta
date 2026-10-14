import { useState } from 'react';
import type { KeyboardEvent } from 'react';
import { useUsers } from '../api/useUsers';
import { useUserVerificationsMap } from '../api/useUserVerifications';
import { PAGE_ELLIPSIS, buildPageWindow } from '../pagination';
import { Header } from '../../components/Header';
import VerificationDetailsDialog from '../../seller-verification/components/VerificationDetailsDialog';

const ROLE_OPTIONS = [
  { value: '', label: 'All Roles' },
  { value: 'user', label: 'User' },
  { value: 'admin', label: 'Administrator' },
] as const;

const SELLER_OPTIONS = [
  { value: '', label: 'All Account Types' },
  { value: 'buyer', label: 'Buyer' },
  { value: 'seller', label: 'Seller' },
] as const;

function formatDate(dateString: string): string {
  const date = new Date(dateString);
  return date.toLocaleDateString('en-PH', {
    year: 'numeric',
    month: 'short',
    day: 'numeric',
  });
}

function statusLabel(status: string | null): string {
  switch (status) {
    case 'submitted':
      return 'Submitted';
    case 'pending_review':
      return 'Pending Review';
    case 'approved':
      return 'Approved';
    case 'rejected':
      return 'Rejected';
    default:
      return '—';
  }
}

export function UsersPage() {
  const [search, setSearch] = useState('');
  const [roleFilter, setRoleFilter] = useState('');
  const [sellerFilter, setSellerFilter] = useState('');
  const [page, setPage] = useState(1);
  const [searchInput, setSearchInput] = useState('');
  const [verificationFilter, setVerificationFilter] = useState<
    '' | 'submitted' | 'pending_review' | 'approved' | 'rejected' | 'none'
  >('');
  const [detailsId, setDetailsId] = useState<number | null>(null);

  const { data, isLoading, isFetching, error, refetch } = useUsers({
    search: search || undefined,
    role: roleFilter || undefined,
    seller_capability: sellerFilter || undefined,
    page,
    per_page: 15,
  });

  // Join with latest verification records per user (deduped server-side)
  const { map: verificationMap, isLoading: verificationsLoading } = useUserVerificationsMap({
    per_page: 100,
  });

  const handleSearch = () => {
    setSearch(searchInput);
    setPage(1);
  };

  const handleSearchKeyDown = (e: React.KeyboardEvent<HTMLInputElement>) => {
    if (e.key === 'Enter') {
      handleSearch();
    }
  };

  const handleRoleChange = (value: string) => {
    setRoleFilter(value);
    setPage(1);
  };

  const handleSellerChange = (value: string) => {
    setSellerFilter(value);
    setPage(1);
  };

  const handleVerificationChange = (
    value: '' | 'submitted' | 'pending_review' | 'approved' | 'rejected' | 'none',
  ) => {
    setVerificationFilter(value);
    setPage(1);
  };

  const handleClearFilters = () => {
    setSearchInput('');
    setSearch('');
    setRoleFilter('');
    setSellerFilter('');
    setVerificationFilter('');
    setPage(1);
  };

  const handlePageChange = (newPage: number) => {
    if (isFetching) return;
    const lastPage = data?.pagination?.last_page ?? 1;
    if (newPage < 1 || newPage > lastPage || newPage === page) return;
    setPage(newPage);
  };

  const handleVerificationClick = (verificationId: number | null) => {
    if (verificationId !== null) {
      setDetailsId(verificationId);
    }
  };

  const handleVerificationKeyDown = (
    event: KeyboardEvent<HTMLSpanElement>,
    verificationId: number | null,
  ) => {
    if (verificationId === null) return;
    if (event.key === 'Enter' || event.key === ' ') {
      event.preventDefault();
      setDetailsId(verificationId);
    }
  };

  if (isLoading || verificationsLoading) {
    return (
      <>
        <Header title="Users" subtitle="Manage platform users" />
        <div className="users-content">
          <div className="users-loading">
            <div className="loading-spinner" />
            <span>Loading users...</span>
          </div>
        </div>
      </>
    );
  }

  if (error) {
    return (
      <>
        <Header title="Users" subtitle="Manage platform users" />
        <div className="users-content">
          <div className="users-error">
            <p className="users-error-text">Failed to load users.</p>
            <button type="button" className="users-retry-button" onClick={() => refetch()}>
              Retry
            </button>
          </div>
        </div>
      </>
    );
  }

  const users = data?.users ?? [];
  const pagination = data?.pagination;

  let displayUsers = users;
  if (verificationFilter) {
    displayUsers = users.filter((u) => {
      const v = verificationMap.get(u.id);
      if (verificationFilter === 'none') {
        return !v?.status;
      }
      return v?.status === verificationFilter;
    });
  }

  const filtersActive = Boolean(
    search || roleFilter || sellerFilter || verificationFilter,
  );

  return (
    <>
      <Header title="Users" subtitle="Manage platform users" />

      <div className="users-content">
        <div className="users-controls">
          <div className="users-search-row">
            <div className="users-search-wrapper">
              <input
                type="text"
                className="users-search-input"
                placeholder="Search by name or email..."
                aria-label="Search users by name or email"
                value={searchInput}
                onChange={(e) => setSearchInput(e.target.value)}
                onKeyDown={handleSearchKeyDown}
              />
              <button
                type="button"
                className="users-search-button"
                onClick={handleSearch}
              >
                Search
              </button>
            </div>

            <div className="users-filters">
              <select
                className="users-filter-select"
                aria-label="Filter by role"
                value={roleFilter}
                onChange={(e) => handleRoleChange(e.target.value)}
              >
                {ROLE_OPTIONS.map((opt) => (
                  <option key={opt.value} value={opt.value}>
                    {opt.label}
                  </option>
                ))}
              </select>

              <select
                className="users-filter-select"
                aria-label="Filter by seller capability"
                value={sellerFilter}
                onChange={(e) => handleSellerChange(e.target.value)}
              >
                {SELLER_OPTIONS.map((opt) => (
                  <option key={opt.value} value={opt.value}>
                    {opt.label}
                  </option>
                ))}
              </select>

              <select
                className="users-filter-select"
                aria-label="Filter by verification status"
                value={verificationFilter}
                onChange={(e) =>
                  handleVerificationChange(
                    e.target.value as
                      | ''
                      | 'submitted'
                      | 'pending_review'
                      | 'approved'
                      | 'rejected'
                      | 'none',
                  )
                }
              >
                <option value="">All Verification Status</option>
                <option value="submitted">Submitted</option>
                <option value="pending_review">Pending Review</option>
                <option value="approved">Approved</option>
                <option value="rejected">Rejected</option>
                <option value="none">No verification</option>
              </select>

              {filtersActive && (
                <button
                  type="button"
                  className="users-search-button"
                  onClick={handleClearFilters}
                >
                  Clear filters
                </button>
              )}
            </div>
          </div>
        </div>

        {verificationFilter && (
          <p className="users-filter-notice" role="note">
            Verification status is applied to the users shown on this page only. Use the
            pagination below to check other pages.
          </p>
        )}

        {users.length === 0 ? (
          <div className="users-empty">
            <p>{filtersActive ? 'No users found matching your criteria.' : 'No users found.'}</p>
          </div>
        ) : (
          <>
            {displayUsers.length === 0 ? (
              <div className="users-empty">
                <p>No users on this page match the selected verification status.</p>
              </div>
            ) : (
              <div
                className={`users-table-container${isFetching ? ' users-table-container--fetching' : ''}`}
                aria-busy={isFetching}
              >
                <table className="users-table">
                  <thead>
                    <tr>
                      <th>Name</th>
                      <th>Email</th>
                      <th>Role</th>
                      <th>Seller Capability</th>
                      <th>Verification Status</th>
                      <th>Created At</th>
                    </tr>
                  </thead>
                  <tbody>
                    {displayUsers.map((user) => {
                      const v = verificationMap.get(user.id);
                      const vStatus = v?.status ?? null;
                      const vLabel = statusLabel(vStatus);
                      return (
                        <tr key={user.id}>
                          <td className="users-name-cell">{user.name}</td>
                          <td className="users-email-cell">{user.email}</td>
                          <td>
                            <span className={`users-badge users-badge--${user.role === 'admin' ? 'admin' : 'user'}`}>
                              {user.role === 'admin' ? 'Administrator' : 'User'}
                            </span>
                          </td>
                          <td>
                            <span className={`users-badge users-badge--${user.seller_capability}`}>
                              {user.seller_capability === 'seller' ? 'Seller' : 'Buyer'}
                            </span>
                          </td>
                          <td>
                            {v && v.status && v.verificationId !== null ? (
                              <span
                                className={`lv-badge lv-badge--${vStatus}`}
                                role="button"
                                tabIndex={0}
                                style={{ cursor: 'pointer' }}
                                onClick={() => handleVerificationClick(v.verificationId)}
                                onKeyDown={(e) => handleVerificationKeyDown(e, v.verificationId)}
                                aria-label={`View verification details for ${user.name}`}
                              >
                                {vLabel}
                              </span>
                            ) : (
                              <span className="users-date-cell">—</span>
                            )}
                          </td>
                          <td className="users-date-cell">{formatDate(user.created_at)}</td>
                        </tr>
                      );
                    })}
                  </tbody>
                </table>
              </div>
            )}

            {pagination && pagination.last_page > 1 && (
              <nav className="users-pagination" aria-label="Users pagination">
                <button
                  type="button"
                  className="users-page-button"
                  disabled={isFetching || pagination.current_page <= 1}
                  onClick={() => handlePageChange(pagination.current_page - 1)}
                  aria-label="Go to previous page"
                >
                  Previous
                </button>

                {buildPageWindow(pagination.current_page, pagination.last_page).map(
                  (item, index) =>
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

                <span className="users-page-info" aria-live="polite">
                  Page {pagination.current_page} of {pagination.last_page}
                  {' '}
                  <span className="users-page-total">({pagination.total} users)</span>
                  {isFetching && <span className="users-page-updating"> Updating…</span>}
                </span>
              </nav>
            )}
          </>
        )}
      </div>

      {detailsId !== null && (
        <VerificationDetailsDialog
          verificationId={detailsId}
          onClose={() => setDetailsId(null)}
        />
      )}
    </>
  );
}
