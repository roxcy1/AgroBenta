import { useState } from 'react';
import { useTransactions } from '../api/useTransactions';

const STATUS_OPTIONS = [
  { value: '', label: 'All Statuses' },
  { value: 'pending', label: 'Pending' },
  { value: 'completed', label: 'Completed' },
  { value: 'cancelled', label: 'Cancelled' },
] as const;

function formatCurrency(value: string): string {
  const num = parseFloat(value);
  if (isNaN(num)) return '\u20B10';
  return `\u20B1${num.toLocaleString('en-PH', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;
}

function formatDate(dateString: string): string {
  const date = new Date(dateString);
  return date.toLocaleDateString('en-PH', {
    year: 'numeric',
    month: 'short',
    day: 'numeric',
  });
}

export function TransactionsPage() {
  const [search, setSearch] = useState('');
  const [statusFilter, setStatusFilter] = useState('');
  const [page, setPage] = useState(1);
  const [searchInput, setSearchInput] = useState('');

  const { data, isLoading, error, refetch } = useTransactions({
    search: search || undefined,
    status: statusFilter || undefined,
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

  const handleStatusChange = (value: string) => {
    setStatusFilter(value);
    setPage(1);
  };

  const handlePageChange = (newPage: number) => {
    setPage(newPage);
  };

  if (isLoading) {
    return (
      <div className="lv-loading">
        <div className="loading-spinner" />
        <span>Loading transactions...</span>
      </div>
    );
  }

  if (error) {
    return (
      <div className="lv-error">
        <p className="lv-error-text">Failed to load transactions.</p>
        <button type="button" className="lv-retry-button" onClick={() => refetch()}>
          Retry
        </button>
      </div>
    );
  }

  const transactions = data?.transactions ?? [];
  const pagination = data?.pagination;

  return (
    <div className="lv-tab-content">
      <div className="lv-controls">
        <div className="lv-search-row">
          <div className="lv-search-wrapper">
            <input
              type="text"
              className="lv-search-input"
              placeholder="Search by ID, buyer, seller, or livestock..."
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

      {transactions.length === 0 ? (
        <div className="lv-empty">
          <p>No transactions found.</p>
        </div>
      ) : (
        <>
          <div className="lv-table-container">
            <table className="lv-table">
              <thead>
                <tr>
                  <th>Transaction ID</th>
                  <th>Buyer</th>
                  <th>Seller</th>
                  <th>Livestock</th>
                  <th>Qty</th>
                  <th>Total Amount</th>
                  <th>Status</th>
                  <th>Date</th>
                </tr>
              </thead>
              <tbody>
                {transactions.map((tx) => (
                  <tr key={tx.id}>
                    <td className="lv-name-cell">#{tx.id}</td>
                    <td className="lv-seller-cell">{tx.buyer.name}</td>
                    <td className="lv-seller-cell">{tx.seller.name}</td>
                    <td>{tx.listing.livestock_type} / {tx.listing.breed}</td>
                    <td>{tx.quantity}</td>
                    <td className="lv-price-cell">{formatCurrency(tx.total_amount)}</td>
                    <td>
                      <span className={`lv-badge lv-badge--${tx.status}`}>
                        {tx.status.charAt(0).toUpperCase() + tx.status.slice(1)}
                      </span>
                    </td>
                    <td className="lv-date-cell">{formatDate(tx.created_at)}</td>
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
                <span className="lv-page-total">({pagination.total} transactions)</span>
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
