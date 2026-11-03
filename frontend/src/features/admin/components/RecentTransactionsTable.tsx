import type { DashboardRecentTransaction } from '../api/useDashboard';
import { formatCurrency, formatDate } from './dashboardFormat';
import { StatusBadge } from './StatusBadge';

interface RecentTransactionsTableProps {
  transactions: DashboardRecentTransaction[];
}

export function RecentTransactionsTable({ transactions }: RecentTransactionsTableProps) {
  if (transactions.length === 0) {
    return (
      <div className="dashboard-empty-state">
        <p>No transactions available yet.</p>
      </div>
    );
  }

  return (
    <div className="dashboard-table-container">
      <table className="dashboard-table">
        <thead>
          <tr>
            <th>Transaction ID</th>
            <th>Buyer</th>
            <th>Seller</th>
            <th>Livestock</th>
            <th>Amount</th>
            <th>Status</th>
            <th>Date</th>
          </tr>
        </thead>
        <tbody>
          {transactions.map((transaction) => (
            <tr key={transaction.id}>
              <td className="lv-name-cell">#{transaction.id}</td>
              <td className="lv-seller-cell">{transaction.buyer?.name ?? '—'}</td>
              <td className="lv-seller-cell">{transaction.seller?.name ?? '—'}</td>
              <td>
                {transaction.listing
                  ? `${transaction.listing.livestock_type} / ${transaction.listing.breed}`
                  : '—'}
              </td>
              <td className="lv-price-cell">{formatCurrency(transaction.total_amount)}</td>
              <td>
                <StatusBadge status={transaction.status} />
              </td>
              <td className="lv-date-cell">{formatDate(transaction.created_at)}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
