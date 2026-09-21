import { ArrowLeftRight, Package, Store, Users as UsersIcon } from 'lucide-react';
import { BarChart, Bar, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer, PieChart, Pie, Cell, Legend } from 'recharts';
import { useDashboard } from '../api/useDashboard';
import { Header } from './Header';

const PIE_COLORS = ['#1B5E20', '#2E7D32', '#4CAF50', '#66BB6A', '#81C784', '#A5D6A7', '#C8E6C9'];

function formatCurrency(value: number): string {
  if (value === 0) return '₱0';
  return `₱${value.toLocaleString('en-PH', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;
}

function formatDate(dateString: string): string {
  const date = new Date(dateString);
  return date.toLocaleDateString('en-PH', {
    month: 'short',
    day: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
  });
}

export function Dashboard() {
  const { data, isLoading, error, refetch } = useDashboard();

  if (isLoading) {
    return (
      <>
        <Header title="Dashboard" subtitle="Welcome, Administrator" />
        <div className="dashboard-content">
          <div className="dashboard-loading">
            <div className="loading-spinner" />
            <span>Loading dashboard data...</span>
          </div>
        </div>
      </>
    );
  }

  if (error) {
    return (
      <>
        <Header title="Dashboard" subtitle="Welcome, Administrator" />
        <div className="dashboard-content">
          <div className="dashboard-error">
            <p className="dashboard-error-text">Failed to load dashboard data.</p>
            <button type="button" className="dashboard-retry-button" onClick={() => refetch()}>
              Retry
            </button>
          </div>
        </div>
      </>
    );
  }

  if (!data) {
    return (
      <>
        <Header title="Dashboard" subtitle="Welcome, Administrator" />
        <div className="dashboard-content">
          <div className="dashboard-empty">
            <p>No dashboard data available.</p>
          </div>
        </div>
      </>
    );
  }

  const { summary, listings, transactions, transaction_trend, livestock_distribution, recent_activities } = data;

  return (
    <>
      <Header title="Dashboard" subtitle="Welcome, Administrator" />

      <div className="dashboard-content">
        <div className="dashboard-welcome">
          <p className="dashboard-welcome-text">
            Here is an overview of your marketplace activity and key metrics.
          </p>
        </div>

        <div className="dashboard-stats-grid">
          <div className="dashboard-stat-card">
            <div className="dashboard-stat-icon dashboard-stat-icon--users">
              <UsersIcon className="dashboard-stat-icon-svg" aria-hidden="true" />
            </div>
            <div className="dashboard-stat-info">
              <span className="dashboard-stat-value">{summary.total_users}</span>
              <span className="dashboard-stat-label">Total Users</span>
            </div>
          </div>

          <div className="dashboard-stat-card">
            <div className="dashboard-stat-icon dashboard-stat-icon--listings">
              <Package className="dashboard-stat-icon-svg" aria-hidden="true" />
            </div>
            <div className="dashboard-stat-info">
              <span className="dashboard-stat-value">{summary.active_listings}</span>
              <span className="dashboard-stat-label">Active Listings</span>
            </div>
          </div>

          <div className="dashboard-stat-card">
            <div className="dashboard-stat-icon dashboard-stat-icon--transactions">
              <ArrowLeftRight className="dashboard-stat-icon-svg" aria-hidden="true" />
            </div>
            <div className="dashboard-stat-info">
              <span className="dashboard-stat-value">{summary.total_transactions}</span>
              <span className="dashboard-stat-label">Transactions</span>
            </div>
          </div>

          <div className="dashboard-stat-card">
            <div className="dashboard-stat-icon dashboard-stat-icon--sellers">
              <Store className="dashboard-stat-icon-svg" aria-hidden="true" />
            </div>
            <div className="dashboard-stat-info">
              <span className="dashboard-stat-value">{summary.approved_sellers}</span>
              <span className="dashboard-stat-label">Approved Sellers</span>
            </div>
          </div>
        </div>

        <div className="dashboard-section">
          <h2 className="dashboard-section-title">Marketplace Overview</h2>

          <div className="dashboard-charts-grid">
            <div className="dashboard-chart-card">
              <h3 className="dashboard-chart-title">Transaction Trend ({new Date().getFullYear()})</h3>
              {transaction_trend.some(item => item.count > 0) ? (
                <ResponsiveContainer width="100%" height={300}>
                  <BarChart data={transaction_trend} margin={{ top: 10, right: 10, left: 0, bottom: 0 }}>
                    <CartesianGrid strokeDasharray="3 3" stroke="#E0E0E0" />
                    <XAxis dataKey="month" tick={{ fontSize: 12 }} stroke="#666666" />
                    <YAxis tick={{ fontSize: 12 }} stroke="#666666" />
                    <Tooltip
                      formatter={(value, name) => [
                        name === 'count' ? String(value) : formatCurrency(Number(value ?? 0)),
                        name === 'count' ? 'Transactions' : 'Revenue',
                      ]}
                      contentStyle={{ fontSize: 13 }}
                    />
                    <Bar dataKey="count" fill="#1B5E20" radius={[2, 2, 0, 0]} name="Transactions" />
                  </BarChart>
                </ResponsiveContainer>
              ) : (
                <div className="dashboard-chart-empty">
                  <p>No transaction data for this year.</p>
                </div>
              )}
            </div>

            <div className="dashboard-chart-card">
              <h3 className="dashboard-chart-title">Livestock Distribution</h3>
              {livestock_distribution.length > 0 ? (
                <ResponsiveContainer width="100%" height={300}>
                  <PieChart>
                    <Pie
                      data={livestock_distribution}
                      cx="50%"
                      cy="50%"
                      innerRadius={60}
                      outerRadius={100}
                      paddingAngle={2}
                      dataKey="count"
                      nameKey="type"
                      label={({ name, value }: { name?: string; value?: number }) => `${name ?? 'Unknown'}: ${value ?? 0}`}
                      labelLine={false}
                    >
                      {livestock_distribution.map((_, index) => (
                        <Cell key={`cell-${index}`} fill={PIE_COLORS[index % PIE_COLORS.length]} />
                      ))}
                    </Pie>
                    <Tooltip formatter={(value) => [String(value ?? 0), 'Listings']} contentStyle={{ fontSize: 13 }} />
                    <Legend />
                  </PieChart>
                </ResponsiveContainer>
              ) : (
                <div className="dashboard-chart-empty">
                  <p>No livestock listings data available.</p>
                </div>
              )}
            </div>
          </div>
        </div>

        <div className="dashboard-section">
          <h2 className="dashboard-section-title">Recent Activities</h2>

          {recent_activities.length > 0 ? (
            <div className="dashboard-table-container">
              <table className="dashboard-table">
                <thead>
                  <tr>
                    <th>Action</th>
                    <th>Description</th>
                    <th>User</th>
                    <th>Date</th>
                  </tr>
                </thead>
                <tbody>
                  {recent_activities.map((activity) => (
                    <tr key={activity.id}>
                      <td>
                        <span className="dashboard-activity-badge">{activity.action}</span>
                      </td>
                      <td className="dashboard-activity-description">{activity.description}</td>
                      <td>{activity.user?.name ?? '—'}</td>
                      <td className="dashboard-activity-date">{formatDate(activity.created_at)}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          ) : (
            <div className="dashboard-empty-state">
              <p>No recent activities recorded.</p>
            </div>
          )}
        </div>

        <div className="dashboard-section">
          <h2 className="dashboard-section-title">Detailed Breakdown</h2>

          <div className="dashboard-breakdown-grid">
            <div className="dashboard-breakdown-card">
              <h4 className="dashboard-breakdown-title">Listings by Status</h4>
              <ul className="dashboard-breakdown-list">
                <li>
                  <span className="dashboard-breakdown-label">Active</span>
                  <span className="dashboard-breakdown-value">{listings.active}</span>
                </li>
                <li>
                  <span className="dashboard-breakdown-label">Pending</span>
                  <span className="dashboard-breakdown-value">{listings.pending}</span>
                </li>
                <li>
                  <span className="dashboard-breakdown-label">Sold</span>
                  <span className="dashboard-breakdown-value">{listings.sold}</span>
                </li>
                <li>
                  <span className="dashboard-breakdown-label">Draft</span>
                  <span className="dashboard-breakdown-value">{listings.draft}</span>
                </li>
                <li>
                  <span className="dashboard-breakdown-label">Inactive</span>
                  <span className="dashboard-breakdown-value">{listings.inactive}</span>
                </li>
              </ul>
            </div>

            <div className="dashboard-breakdown-card">
              <h4 className="dashboard-breakdown-title">Transactions by Status</h4>
              <ul className="dashboard-breakdown-list">
                <li>
                  <span className="dashboard-breakdown-label">Pending</span>
                  <span className="dashboard-breakdown-value">{transactions.pending}</span>
                </li>
                <li>
                  <span className="dashboard-breakdown-label">Completed</span>
                  <span className="dashboard-breakdown-value">{transactions.completed}</span>
                </li>
                <li>
                  <span className="dashboard-breakdown-label">Cancelled</span>
                  <span className="dashboard-breakdown-value">{transactions.cancelled}</span>
                </li>
              </ul>
            </div>

            <div className="dashboard-breakdown-card">
              <h4 className="dashboard-breakdown-title">User Accounts</h4>
              <ul className="dashboard-breakdown-list">
                <li>
                  <span className="dashboard-breakdown-label">Total Users</span>
                  <span className="dashboard-breakdown-value">{summary.total_users}</span>
                </li>
                <li>
                  <span className="dashboard-breakdown-label">Buyers</span>
                  <span className="dashboard-breakdown-value">{summary.buyer_accounts}</span>
                </li>
                <li>
                  <span className="dashboard-breakdown-label">Approved Sellers</span>
                  <span className="dashboard-breakdown-value">{summary.approved_sellers}</span>
                </li>
              </ul>
            </div>
          </div>
        </div>
      </div>
    </>
  );
}
