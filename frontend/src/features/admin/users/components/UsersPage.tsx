import { useState } from 'react';
import { useSearchParams } from 'react-router-dom';
import type { KeyboardEvent } from 'react';
import { UsersRound } from 'lucide-react';
import { parsePositiveInt, resolveDeepLinkedRecord } from '../../../../lib/queryParams';
import { useAdminUser, useUserCounts, useUsers } from '../api/useUsers';
import type { AdminUser } from '../api/useUsers';
import { useUserVerificationsMap } from '../api/useUserVerifications';
import { PAGE_ELLIPSIS, buildPageWindow } from '../pagination';
import { Header } from '../../components/Header';
import UserStatsCards from './UserStatsCards';
import type { UserCardKey } from './UserStatsCards';
import UserDetailsDialog from './UserDetailsDialog';
import EditUserDialog from './EditUserDialog';
import DeleteUserDialog from './DeleteUserDialog';
import UserActionsMenu from './UserActionsMenu';
import VerificationDetailsDialog from '../../seller-verification/components/VerificationDetailsDialog';
import { statusBadgeClass, statusLabel } from '../../../../lib/status';
import { formatDate } from '../../../../lib/format';
import { emptyListMessage } from '../../../../lib/emptyState';
import './UsersPage.css';

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

const ROWS_PER_PAGE_OPTIONS = [10, 15, 25, 50, 100] as const;

export function UsersPage() {
  const [search, setSearch] = useState('');
  const [roleFilter, setRoleFilter] = useState('');
  const [sellerFilter, setSellerFilter] = useState('');
  const [page, setPage] = useState(1);
  const [perPage, setPerPage] = useState(15);
  const [searchInput, setSearchInput] = useState('');
  const [verificationFilter, setVerificationFilter] = useState<
    '' | 'submitted' | 'pending_review' | 'approved' | 'rejected' | 'none'
  >('');
  const [detailsId, setDetailsId] = useState<number | null>(null);
  const [detailsUser, setDetailsUser] = useState<AdminUser | null>(null);
  const [actionsUserId, setActionsUserId] = useState<number | null>(null);
  const [editingUser, setEditingUser] = useState<AdminUser | null>(null);
  const [deletingUser, setDeletingUser] = useState<AdminUser | null>(null);
  const [searchParams] = useSearchParams();
  const linkedUserId = parsePositiveInt(searchParams.get('user'));
  const [dismissedLinkId, setDismissedLinkId] = useState<number | null>(null);

  // The users surface has no detail screen, so a `?user=` deep link is resolved
  // to the account and applied as a search filter. The list is derived from the
  // URL rather than synced from the fetched record, so no effect is needed.
  const { data: linkedUser, isError: linkedUserFailed } = useAdminUser(linkedUserId);
  const linkedState = resolveDeepLinkedRecord({
    entity: 'User',
    id: linkedUserId,
    dismissedId: dismissedLinkId,
    record: linkedUser,
    isError: linkedUserFailed,
  });
  const deepLinkedEmail = linkedState.record?.email ?? '';
  const effectiveSearch = search || deepLinkedEmail;

  const { data, isLoading, isFetching, error, refetch } = useUsers({
    search: effectiveSearch || undefined,
    role: roleFilter || undefined,
    seller_capability: sellerFilter || undefined,
    page,
    per_page: perPage,
  });

  // Join with latest verification records per user (deduped server-side)
  const { map: verificationMap, isLoading: verificationsLoading } = useUserVerificationsMap({
    per_page: 100,
  });

  const { data: counts } = useUserCounts();
  const pageHeader = (
    <Header
      title="Users"
      subtitle="Manage platform users"
      pageIcon={UsersRound}
      profileRole="Administrator"
      showProfileChevron
    />
  );

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

  // Each card selects one filter dimension: account type (buyer/seller) or role
  // (admin). Selecting a card clears the other dimension, and selecting the
  // active card or "Total Users" clears both, so the cards stay mutually
  // exclusive and mirror the table's own filters.
  const activeCardKey: UserCardKey | '' =
    sellerFilter === 'buyer'
      ? 'buyer'
      : sellerFilter === 'seller'
        ? 'seller'
        : roleFilter === 'admin'
          ? 'admin'
          : roleFilter === '' && sellerFilter === ''
            ? 'all'
            : '';

  const handleCardSelect = (key: UserCardKey) => {
    if (key === activeCardKey && key !== 'all') {
      setRoleFilter('');
      setSellerFilter('');
    } else if (key === 'buyer') {
      setSellerFilter('buyer');
      setRoleFilter('');
    } else if (key === 'seller') {
      setSellerFilter('seller');
      setRoleFilter('');
    } else if (key === 'admin') {
      setRoleFilter('admin');
      setSellerFilter('');
    } else {
      setRoleFilter('');
      setSellerFilter('');
    }
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
    if (linkedUserId !== null) setDismissedLinkId(linkedUserId);
  };

  const handleDismissLinkedNotice = () => {
    if (linkedUserId !== null) setDismissedLinkId(linkedUserId);
  };

  const handlePageChange = (newPage: number) => {
    if (isFetching) return;
    const lastPage = data?.pagination?.last_page ?? 1;
    if (newPage < 1 || newPage > lastPage || newPage === page) return;
    setPage(newPage);
  };

  const handlePerPageChange = (value: string) => {
    const nextPerPage = Number(value);
    if (!ROWS_PER_PAGE_OPTIONS.includes(nextPerPage as (typeof ROWS_PER_PAGE_OPTIONS)[number])) return;
    setPerPage(nextPerPage);
    setPage(1);
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

  const handleRowKeyDown = (
    event: KeyboardEvent<HTMLTableRowElement>,
    user: AdminUser,
  ) => {
    if (event.target !== event.currentTarget) return;
    if (event.key === 'Enter' || event.key === ' ') {
      event.preventDefault();
      setDetailsUser(user);
    }
  };

  if (isLoading || verificationsLoading) {
    return (
      <div className="users-page-shell">
        {pageHeader}
        <div className="users-content lv-content">
          <UserStatsCards counts={counts} activeKey={activeCardKey} onSelect={handleCardSelect} />
          <div className="users-loading">
            <div className="loading-spinner" />
            <span>Loading users...</span>
          </div>
        </div>
      </div>
    );
  }

  if (error) {
    return (
      <div className="users-page-shell">
        {pageHeader}
        <div className="users-content lv-content">
          <UserStatsCards counts={counts} activeKey={activeCardKey} onSelect={handleCardSelect} />
          <div className="users-error">
            <p className="users-error-text">Failed to load users.</p>
            <button type="button" className="users-retry-button" onClick={() => refetch()}>
              Retry
            </button>
          </div>
        </div>
      </div>
    );
  }

  const users = data?.users ?? [];
  const pagination = data?.pagination;
  const resultStart = pagination && pagination.total > 0
    ? (pagination.current_page - 1) * pagination.per_page + 1
    : 0;
  const resultEnd = pagination && pagination.total > 0
    ? Math.min((pagination.current_page - 1) * pagination.per_page + users.length, pagination.total)
    : 0;

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
    search || deepLinkedEmail || roleFilter || sellerFilter || verificationFilter,
  );
  return (
    <>
      <div className="users-page-shell">
        {pageHeader}

        <div className="users-content lv-content">
        <UserStatsCards counts={counts} activeKey={activeCardKey} onSelect={handleCardSelect} />

        <div className="users-controls lv-controls">
          <div className="users-search-row lv-search-row">
            <div className="users-search-wrapper lv-search-wrapper">
              <input
                type="text"
                className="users-search-input lv-search-input"
                placeholder="Search by name or email..."
                aria-label="Search users by name or email"
                value={searchInput || deepLinkedEmail}
                onChange={(e) => setSearchInput(e.target.value)}
                onKeyDown={handleSearchKeyDown}
              />
              <button
                type="button"
                className="users-search-button lv-search-button"
                onClick={handleSearch}
              >
                Search
              </button>
            </div>

            <div className="users-filters lv-filters">
              <select
                className="users-filter-select lv-filter-select"
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
                className="users-filter-select lv-filter-select"
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
                className="users-filter-select lv-filter-select"
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
                  className="users-search-button lv-search-button"
                  onClick={handleClearFilters}
                >
                  Clear filters
                </button>
              )}
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

        {verificationFilter && (
          <p className="users-filter-notice" role="note">
            Verification status is applied to the users shown on this page only. Use the
            pagination below to check other pages.
          </p>
        )}

        {users.length === 0 ? (
          <div className="users-empty">
            <p>{emptyListMessage('users', filtersActive)}</p>
          </div>
        ) : (
          <>
            {displayUsers.length === 0 ? (
              <div className="users-empty">
                <p>No users on this page match the selected verification status.</p>
              </div>
            ) : (
              <div
                className={`users-table-container lv-table-container${isFetching ? ' users-table-container--fetching' : ''}`}
                aria-busy={isFetching}
              >
                <table className="users-table lv-table">
                  <thead>
                    <tr>
                      <th>Name</th>
                      <th>Email</th>
                      <th>Role</th>
                      <th>Seller Capability</th>
                      <th>Verification Status</th>
                      <th>Created At</th>
                      <th className="users-actions-heading">Actions</th>
                    </tr>
                  </thead>
                  <tbody>
                    {displayUsers.map((user) => {
                      const v = verificationMap.get(user.id);
                      const vStatus = v?.status ?? null;
                      const vLabel = vStatus ? statusLabel(vStatus) : '—';
                      return (
                        <tr
                          key={user.id}
                          className="users-row--clickable lv-listings-row"
                          tabIndex={0}
                          aria-label={`View details for ${user.name}`}
                          onClick={() => setDetailsUser(user)}
                          onKeyDown={(event) => handleRowKeyDown(event, user)}
                        >
                          <td className="users-name-cell lv-name-cell" data-label="Name" title={user.name}>{user.name}</td>
                          <td className="users-email-cell" data-label="Email" title={user.email}>{user.email}</td>
                          <td data-label="Role">
                            <span className={`users-badge users-badge--${user.role === 'admin' ? 'admin' : 'user'}`}>
                              {user.role === 'admin' ? 'Administrator' : 'User'}
                            </span>
                          </td>
                          <td data-label="Seller Capability">
                            <span className={`users-badge users-badge--${user.seller_capability}`}>
                              {user.seller_capability === 'seller' ? 'Seller' : 'Buyer'}
                            </span>
                          </td>
                          <td data-label="Verification Status">
                            {v && v.status && v.verificationId !== null ? (
                              <span
                                className={statusBadgeClass(v.status)}
                                role="button"
                                tabIndex={0}
                                style={{ cursor: 'pointer' }}
                                onClick={(e) => {
                                  e.stopPropagation();
                                  handleVerificationClick(v.verificationId);
                                }}
                                onKeyDown={(e) => {
                                  e.stopPropagation();
                                  handleVerificationKeyDown(e, v.verificationId);
                                }}
                                aria-label={`View verification details for ${user.name}`}
                              >
                                {vLabel}
                              </span>
                            ) : (
                              <span className="users-date-cell">—</span>
                            )}
                          </td>
                          <td className="users-date-cell" data-label="Created At">{formatDate(user.created_at)}</td>
                          <td
                            className="users-actions-cell"
                            data-label="Actions"
                            onClick={(event) => event.stopPropagation()}
                          >
                            <UserActionsMenu
                              user={user}
                              isOpen={actionsUserId === user.id}
                              onToggle={() =>
                                setActionsUserId((current) => current === user.id ? null : user.id)
                              }
                              onClose={() => setActionsUserId(null)}
                              onEdit={() => setEditingUser(user)}
                              onDelete={() => setDeletingUser(user)}
                            />
                          </td>
                        </tr>
                      );
                    })}
                  </tbody>
                </table>
              </div>
            )}

            {pagination && (
              <nav className="users-pagination" aria-label="Users pagination">
                <span className="users-page-info" aria-live="polite">
                  Showing {resultStart}–{resultEnd} of {pagination.total} users
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

                    {pagination.last_page > 1 && buildPageWindow(pagination.current_page, pagination.last_page).map(
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
                  </div>
                </div>
              </nav>
            )}
          </>
        )}
        </div>
      </div>

      {detailsId !== null && (
        <VerificationDetailsDialog
          verificationId={detailsId}
          onClose={() => setDetailsId(null)}
        />
      )}

      {detailsUser !== null && (
        <UserDetailsDialog
          user={detailsUser}
          verificationStatus={verificationMap.get(detailsUser.id)?.status ?? null}
          onClose={() => setDetailsUser(null)}
        />
      )}

      {editingUser !== null && (
        <EditUserDialog
          key={editingUser.id}
          user={editingUser}
          onClose={() => setEditingUser(null)}
        />
      )}

      {deletingUser !== null && (
        <DeleteUserDialog
          key={deletingUser.id}
          user={deletingUser}
          onClose={() => setDeletingUser(null)}
          onDeleted={() => {
            if (data?.users.length === 1 && page > 1) setPage(page - 1);
          }}
        />
      )}
    </>
  );
}
