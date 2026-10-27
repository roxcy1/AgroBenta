import { useState } from 'react';
import { useSearchParams } from 'react-router-dom';
import { parsePositiveInt, resolveDeepLinkedRecord } from '../../../../lib/queryParams';
import {
  useTransactions,
  useTransaction,
  useTransactionCounts,
  fetchAllTransactions,
} from '../api/useTransactions';
import type { Transaction } from '../api/useTransactions';
import { buildTransactionsCsv, buildTransactionsFilename, downloadCsv } from '../csv';
import TransactionDetailDialog from './TransactionDetailDialog';
import TransactionStatsCards from './TransactionStatsCards';

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
  const [dateFrom, setDateFrom] = useState('');
  const [dateTo, setDateTo] = useState('');
  const [appliedDates, setAppliedDates] = useState<{ date_from?: string; date_to?: string }>({});
  const [page, setPage] = useState(1);
  const [searchInput, setSearchInput] = useState('');
  const [selectedTransaction, setSelectedTransaction] = useState<Transaction | null>(null);
  const [isExporting, setIsExporting] = useState(false);
  const [exportError, setExportError] = useState<string | null>(null);
  const [searchParams] = useSearchParams();
  const linkedTransactionId = parsePositiveInt(searchParams.get('transaction'));
  const [dismissedLinkId, setDismissedLinkId] = useState<number | null>(null);

  const { data, isLoading, error, refetch } = useTransactions({
    search: search || undefined,
    status: statusFilter || undefined,
    date_from: appliedDates.date_from,
    date_to: appliedDates.date_to,
    page,
    per_page: 15,
  });

  const { data: counts } = useTransactionCounts();
  const { data: linkedTransaction, isError: linkedTransactionFailed } =
    useTransaction(linkedTransactionId);

  // A deep link opens the transaction it names even when that row is not on the
  // page the list is showing. The dialog's record is derived from the query
  // result so the URL stays the single source of truth for the open dialog.
  const linkedState = resolveDeepLinkedRecord({
    entity: 'Transaction',
    id: linkedTransactionId,
    dismissedId: dismissedLinkId,
    record: linkedTransaction,
    isError: linkedTransactionFailed,
  });
  const activeTransaction = selectedTransaction ?? linkedState.record;

  const handleCloseTransaction = () => {
    setSelectedTransaction(null);
    if (linkedTransactionId !== null) setDismissedLinkId(linkedTransactionId);
  };

  const handleDismissLinkedNotice = () => {
    if (linkedTransactionId !== null) setDismissedLinkId(linkedTransactionId);
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

  const handleStatusChange = (value: string) => {
    setStatusFilter(value);
    setPage(1);
  };

  const handleStatusCardSelect = (status: string) => {
    setStatusFilter((current) => (current === status ? '' : status));
    setPage(1);
  };

  const handleApplyDates = () => {
    const filters: { date_from?: string; date_to?: string } = {};
    if (dateFrom) filters.date_from = dateFrom;
    if (dateTo) filters.date_to = dateTo;
    setAppliedDates(filters);
    setPage(1);
  };

  const handleClearDates = () => {
    setDateFrom('');
    setDateTo('');
    setAppliedDates({});
    setPage(1);
  };

  const handlePageChange = (newPage: number) => {
    setPage(newPage);
  };

  const handleExportCsv = async () => {
    if (isExporting) return;

    setIsExporting(true);
    setExportError(null);

    try {
      const transactionsToExport = await fetchAllTransactions({
        search: search || undefined,
        status: statusFilter || undefined,
        date_from: appliedDates.date_from,
        date_to: appliedDates.date_to,
      });
      downloadCsv(buildTransactionsFilename(), buildTransactionsCsv(transactionsToExport));
    } catch {
      setExportError('Failed to export transactions. Please try again.');
    } finally {
      setIsExporting(false);
    }
  };

  const transactions = data?.transactions ?? [];
  const pagination = data?.pagination;

  return (
    <div className="lv-tab-content">
      <TransactionStatsCards
        counts={counts}
        activeStatus={statusFilter}
        onSelect={handleStatusCardSelect}
      />

      {isLoading ? (
        <div className="lv-loading">
          <div className="loading-spinner" />
          <span>Loading transactions...</span>
        </div>
      ) : error ? (
        <div className="lv-error">
          <p className="lv-error-text">Failed to load transactions.</p>
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

              <button
                type="button"
                className="reports-clear-button"
                onClick={handleExportCsv}
                disabled={isExporting}
              >
                {isExporting ? 'Exporting…' : 'Export CSV'}
              </button>
            </div>

            <div className="reports-filter-row">
              <div className="reports-filter-group">
                <label className="reports-filter-label" htmlFor="transactions-date-from">
                  From Date
                </label>
                <input
                  id="transactions-date-from"
                  type="date"
                  className="reports-filter-input"
                  value={dateFrom}
                  onChange={(e) => setDateFrom(e.target.value)}
                />
              </div>

              <div className="reports-filter-group">
                <label className="reports-filter-label" htmlFor="transactions-date-to">
                  To Date
                </label>
                <input
                  id="transactions-date-to"
                  type="date"
                  className="reports-filter-input"
                  value={dateTo}
                  onChange={(e) => setDateTo(e.target.value)}
                />
              </div>

              <div className="reports-filter-actions">
                <button type="button" className="lv-search-button" onClick={handleApplyDates}>
                  Apply
                </button>
                {(dateFrom || dateTo) && (
                  <button type="button" className="reports-clear-button" onClick={handleClearDates}>
                    Clear
                  </button>
                )}
              </div>
            </div>
          </div>

          {exportError && <p className="lv-error-text">{exportError}</p>}

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
                      <th>Actions</th>
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
                        <td>
                          <div className="lv-action-buttons">
                            <button
                              type="button"
                              className="lv-action-btn lv-action-btn--view"
                              onClick={() => setSelectedTransaction(tx)}
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
        </>
      )}

      {activeTransaction && (
        <TransactionDetailDialog
          transaction={activeTransaction}
          onClose={handleCloseTransaction}
        />
      )}
    </div>
  );
}
