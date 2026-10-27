import { Link } from 'react-router-dom';
import {
  ArrowLeftRight,
  ArrowRight,
  Clock,
  PackageCheck,
  Store,
  Users as UsersIcon,
} from 'lucide-react';
import {
  BarChart,
  Bar,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  ResponsiveContainer,
  PieChart,
  Pie,
  Cell,
  Legend,
} from 'recharts';
import { useDashboard } from '../api/useDashboard';
import { useReports } from '../reports/api/useReports';
import { formatDate } from './dashboardFormat';
import { RecentListingsTable } from './RecentListingsTable';
import { RecentTransactionsTable } from './RecentTransactionsTable';
import { TopNavBar } from './TopNavBar';

const PIE_COLORS = ['#1B5E20', '#2E7D32', '#4CAF50', '#66BB6A', '#81C784', '#A5D6A7', '#C8E6C9'];

export function Dashboard() {
  const { data, isLoading, error, refetch } = useDashboard();
  const {
    data: reportsData,
    isLoading: reportsLoading,
    error: reportsError,
    refetch: refetchReports,
  } = useReports({});

  if (isLoading) {
    return (
      <>
        <TopNavBar />
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
        <TopNavBar />
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
        <TopNavBar />
        <div className="dashboard-content">
          <div className="dashboard-empty">
            <p>No dashboard data available.</p>
          </div>
        </div>
      </>
    );
  }

  const {
    summary,
    listings,
    transactions,
    transaction_trend,
    livestock_distribution,
    recent_activities,
    recent_listings = [],
    recent_transactions = [],
  } = data;

  const now = new Date();
  const currentMonthIndex = now.getMonth();
  const currentMonthLabel = now.toLocaleDateString('en-PH', {
    month: 'short',
    year: 'numeric',
  });
  const transactionsThisMonth = transaction_trend[currentMonthIndex]?.count ?? 0;

  const listingStatusData = [
    { status: 'Draft', count: listings.draft, color: '#9E9E9E' },
    { status: 'Pending', count: listings.pending, color: '#F57F17' },
    { status: 'Active', count: listings.active, color: '#1B5E20' },
    { status: 'Sold', count: listings.sold, color: '#1565C0' },
    { status: 'Inactive', count: listings.inactive, color: '#BDBDBD' },
  ];

  const approvedVerifications = reportsData?.seller_verifications.approved ?? 0;
  const rejectedVerifications = reportsData?.seller_verifications.rejected ?? 0;
  const verificationOutcomeData = [
    { outcome: 'Approved', count: approvedVerifications, color: '#2E7D32' },
    { outcome: 'Rejected', count: rejectedVerifications, color: '#C62828' },
  ];

  return (
    <>
      <TopNavBar />

      <div className="dashboard-content">
        <div className="dashboard-welcome">
          <p className="dashboard-welcome-text">
            Here is an overview of your marketplace activity and key metrics.
          </p>
        </div>

        <div className="dashboard-stats-grid dashboard-stats-grid--five">
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
            <div className="dashboard-stat-icon dashboard-stat-icon--sellers">
              <Store className="dashboard-stat-icon-svg" aria-hidden="true" />
            </div>
            <div className="dashboard-stat-info">
              <span className="dashboard-stat-value">{summary.approved_sellers}</span>
              <span className="dashboard-stat-label">Active Sellers</span>
            </div>
          </div>

          <div className="dashboard-stat-card">
            <div className="dashboard-stat-icon dashboard-stat-icon--listings">
              <PackageCheck className="dashboard-stat-icon-svg" aria-hidden="true" />
            </div>
            <div className="dashboard-stat-info">
              <span className="dashboard-stat-value">{summary.active_listings}</span>
              <span className="dashboard-stat-label">Active Listings</span>
            </div>
          </div>

          <Link
            to="/seller-verification?status=pending_review"
            className="dashboard-stat-card dashboard-stat-card--pending dashboard-stat-card--link"
          >
            <div className="dashboard-stat-icon dashboard-stat-icon--pending">
              <Clock className="dashboard-stat-icon-svg" aria-hidden="true" />
            </div>
            <div className="dashboard-stat-info">
              <span className="dashboard-stat-value">{summary.pending_verifications ?? 0}</span>
              <span className="dashboard-stat-label">Pending Verifications</span>
              <span className="dashboard-stat-pending-action">
                Review queue
                <ArrowRight className="dashboard-stat-pending-arrow" aria-hidden="true" />
              </span>
            </div>
          </Link>

          <div className="dashboard-stat-card">
            <div className="dashboard-stat-icon dashboard-stat-icon--transactions">
              <ArrowLeftRight className="dashboard-stat-icon-svg" aria-hidden="true" />
            </div>
            <div className="dashboard-stat-info">
              <span className="dashboard-stat-value">{transactionsThisMonth}</span>
              <span className="dashboard-stat-label">Transactions This Month</span>
              <span className="dashboard-stat-sublabel">{currentMonthLabel}</span>
            </div>
          </div>
        </div>

        <div className="dashboard-section">
          <h2 className="dashboard-section-title">Marketplace Overview</h2>

          <div className="dashboard-charts-grid dashboard-charts-grid--flow">
            <div className="dashboard-chart-card">
              <h3 className="dashboard-chart-title">Listings by Status</h3>
              {listings.total > 0 ? (
                <ResponsiveContainer width="100%" height={260}>
                  <BarChart
                    data={listingStatusData}
                    layout="vertical"
                    margin={{ top: 10, right: 16, left: 0, bottom: 0 }}
                  >
                    <CartesianGrid strokeDasharray="3 3" stroke="#E0E0E0" horizontal={false} />
                    <XAxis type="number" allowDecimals={false} tick={{ fontSize: 12 }} stroke="#666666" />
                    <YAxis type="category" dataKey="status" width={82} tick={{ fontSize: 12 }} stroke="#666666" />
                    <Tooltip formatter={(value) => [String(value ?? 0), 'Listings']} contentStyle={{ fontSize: 13 }} />
                    <Bar dataKey="count" radius={[0, 2, 2, 0]} name="Listings">
                      {listingStatusData.map((entry) => (
                        <Cell key={entry.status} fill={entry.color} />
                      ))}
                    </Bar>
                  </BarChart>
                </ResponsiveContainer>
              ) : (
                <div className="dashboard-chart-empty">
                  <p>No listing data available.</p>
                </div>
              )}
              <p className="dashboard-chart-caption">
                Current counts by status. Administrator approval is the only path from
                Pending to Active (D-02) — this shows current totals, not a transition history.
              </p>
            </div>

            <div className="dashboard-chart-card">
              <h3 className="dashboard-chart-title">Verifications by Outcome</h3>
              {reportsLoading ? (
                <div className="dashboard-chart-empty">
                  <div className="loading-spinner" />
                </div>
              ) : reportsError ? (
                <div className="dashboard-chart-empty">
                  <p>Failed to load verification data.</p>
                  <button type="button" className="dashboard-retry-button" onClick={() => refetchReports()}>
                    Retry
                  </button>
                </div>
              ) : approvedVerifications + rejectedVerifications > 0 ? (
                <ResponsiveContainer width="100%" height={260}>
                  <BarChart
                    data={verificationOutcomeData}
                    margin={{ top: 10, right: 16, left: 0, bottom: 0 }}
                  >
                    <CartesianGrid strokeDasharray="3 3" stroke="#E0E0E0" />
                    <XAxis dataKey="outcome" tick={{ fontSize: 12 }} stroke="#666666" />
                    <YAxis allowDecimals={false} tick={{ fontSize: 12 }} stroke="#666666" />
                    <Tooltip formatter={(value) => [String(value ?? 0), 'Verifications']} contentStyle={{ fontSize: 13 }} />
                    <Bar dataKey="count" radius={[2, 2, 0, 0]} name="Verifications">
                      {verificationOutcomeData.map((entry) => (
                        <Cell key={entry.outcome} fill={entry.color} />
                      ))}
                    </Bar>
                  </BarChart>
                </ResponsiveContainer>
              ) : (
                <div className="dashboard-chart-empty">
                  <p>No decided verifications yet.</p>
                </div>
              )}
              <p className="dashboard-chart-caption">
                Approved versus rejected outcomes to date. Rejected applications may require
                seller follow-up.
              </p>
            </div>

            <div className="dashboard-chart-card">
              <h3 className="dashboard-chart-title">Transactions Over Time (Monthly, {now.getFullYear()})</h3>
              {transaction_trend.some(item => item.count > 0) ? (
                <ResponsiveContainer width="100%" height={260}>
                  <BarChart data={transaction_trend} margin={{ top: 10, right: 10, left: 0, bottom: 0 }}>
                    <CartesianGrid strokeDasharray="3 3" stroke="#E0E0E0" />
                    <XAxis dataKey="month" tick={{ fontSize: 12 }} stroke="#666666" />
                    <YAxis allowDecimals={false} tick={{ fontSize: 12 }} stroke="#666666" />
                    <Tooltip formatter={(value) => [String(value ?? 0), 'Transactions']} contentStyle={{ fontSize: 13 }} />
                    <Bar dataKey="count" fill="#1B5E20" radius={[2, 2, 0, 0]} name="Transactions" />
                  </BarChart>
                </ResponsiveContainer>
              ) : (
                <div className="dashboard-chart-empty">
                  <p>No transaction data for this year.</p>
                </div>
              )}
              <p className="dashboard-chart-caption">
                Monthly buckets for the current calendar year — not a rolling 30-day total,
                and not a measure of completed payments.
              </p>
            </div>

            <div className="dashboard-chart-card">
              <h3 className="dashboard-chart-title">Livestock Listings Overview</h3>
              {livestock_distribution.length > 0 ? (
                <ResponsiveContainer width="100%" height={260}>
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
          <div className="dashboard-section-header">
            <h2 className="dashboard-section-title">Recent Livestock Listings</h2>
            <Link to="/livestock" className="dashboard-view-all">View all</Link>
          </div>

          <RecentListingsTable listings={recent_listings} />
        </div>

        <div className="dashboard-section">
          <div className="dashboard-section-header">
            <h2 className="dashboard-section-title">Recent Transactions</h2>
            <Link to="/transactions" className="dashboard-view-all">View all</Link>
          </div>
          <p className="dashboard-section-caption">
            Amounts shown are recorded arrangement values — not revenue, earnings, or payments
            processed by AgroBenta.
          </p>

          <RecentTransactionsTable transactions={recent_transactions} />
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
