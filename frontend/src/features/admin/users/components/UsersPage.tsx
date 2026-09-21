import { useState } from 'react';
import { useUsers } from '../api/useUsers';
import { Header } from '../../components/Header';

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

export function UsersPage() {
  const [search, setSearch] = useState('');
  const [roleFilter, setRoleFilter] = useState('');
  const [sellerFilter, setSellerFilter] = useState('');
  const [page, setPage] = useState(1);
  const [searchInput, setSearchInput] = useState('');

  const { data, isLoading, error, refetch } = useUsers({
    search: search || undefined,
    role: roleFilter || undefined,
    seller_capability: sellerFilter || undefined,
    page,
    per_page: 15,
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

  const handlePageChange = (newPage: number) => {
    setPage(newPage);
  };

  if (isLoading) {
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
                value={sellerFilter}
                onChange={(e) => handleSellerChange(e.target.value)}
              >
                {SELLER_OPTIONS.map((opt) => (
                  <option key={opt.value} value={opt.value}>
                    {opt.label}
                  </option>
                ))}
              </select>
            </div>
          </div>
        </div>

        {users.length === 0 ? (
          <div className="users-empty">
            <p>No users found.</p>
          </div>
        ) : (
          <>
            <div className="users-table-container">
              <table className="users-table">
                <thead>
                  <tr>
                    <th>Name</th>
                    <th>Email</th>
                    <th>Role</th>
                    <th>Account Type</th>
                    <th>Joined</th>
                  </tr>
                </thead>
                <tbody>
                  {users.map((user) => (
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
                      <td className="users-date-cell">{formatDate(user.created_at)}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>

            {pagination && pagination.last_page > 1 && (
              <div className="users-pagination">
                <button
                  type="button"
                  className="users-page-button"
                  disabled={pagination.current_page <= 1}
                  onClick={() => handlePageChange(pagination.current_page - 1)}
                >
                  Previous
                </button>
                <span className="users-page-info">
                  Page {pagination.current_page} of {pagination.last_page}
                  {' '}
                  <span className="users-page-total">({pagination.total} users)</span>
                </span>
                <button
                  type="button"
                  className="users-page-button"
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
    </>
  );
}
