import { Link } from 'react-router-dom';
import {
  ArrowLeftRight,
  ArrowRight,
  Beef,
  ChartNoAxesCombined,
  Clock,
  Home,
  Layers,
  PackageCheck,
  ShieldCheck,
  Store,
  TrendingUp,
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
import { formatDateTime } from '../../../lib/format';
import { RecentListingsTable } from './RecentListingsTable';
import { RecentTransactionsTable } from './RecentTransactionsTable';
import { Header } from './Header';
import { statusChartColor, statusLabel } from '../../../lib/status';
import { CHART_AXIS, CHART_BAR, CHART_GRID, CHART_PIE_COLORS, CHART_TICK, CHART_TOOLTIP_STYLE } from '../../../lib/chartTheme';
import './Dashboard.css';

export function Dashboard() {
  const { data, isLoading, error, refetch } = useDashboard();
  const {
    data: reportsData,
    isLoading: reportsLoading,
    error: reportsError,
    refetch: refetchReports,
  } = useReports({});
  const pageHeader = (
    <Header
      title="Dashboard"
      subtitle="Overview of marketplace activity and key metrics"
      pageIcon={Home}
      profileRole="Administrator"
      showProfileChevron
    />
  );

  if (isLoading) {
    return (
      <div className="dashboard-page-shell">
        {pageHeader}
        <div className="dashboard-content">
          <div className="dashboard-loading">
            <div className="loading-spinner" />
            <span>Loading dashboard data...</span>
          </div>
        </div>
      </div>
    );
  }

  if (error) {
    return (
      <div className="dashboard-page-shell">
        {pageHeader}
        <div className="dashboard-content">
          <div className="dashboard-error">
            <p className="dashboard-error-text">Failed to load dashboard data.</p>
            <button type="button" className="dashboard-retry-button" onClick={() => refetch()}>
              Retry
            </button>
          </div>
        </div>
      </div>
    );
  }

  if (!data) {
    return (
      <div className="dashboard-page-shell">
        {pageHeader}
        <div className="dashboard-content">
          <div className="dashboard-empty">
            <p>No dashboard data available.</p>
          </div>
        </div>
      </div>
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

  const listingStatusData = (['draft', 'pending', 'active', 'sold', 'inactive'] as const).map((key) => ({
    status: statusLabel(key),
    count: listings[key],
    color: key === 'active' ? '#15803d' : '#c4cbc6',
  }));

  const totalLivestockListings = livestock_distribution.reduce((total, item) => total + item.count, 0);

  const approvedVerifications = reportsData?.seller_verifications.approved ?? 0;
  const rejectedVerifications = reportsData?.seller_verifications.rejected ?? 0;
  const verificationOutcomeData = [
    {
      outcome: statusLabel('approved'),
      count: approvedVerifications,
      color: statusChartColor('approved'),
    },
    {
      outcome: statusLabel('rejected'),
      count: rejectedVerifications,
      color: statusChartColor('rejected'),
    },
  ];

  return (
    <div className="dashboard-page-shell">
      {pageHeader}
      <div className="dashboard-content">
        <div className="dashboard-stats-grid dashboard-stats-grid--five">
          <div className="dashboard-stat-card dashboard-stat-card--tone-users">
            <div className="dashboard-stat-icon dashboard-stat-icon--users">
              <UsersIcon className="dashboard-stat-icon-svg" aria-hidden="true" />
            </div>
            <div className="dashboard-stat-info">
              <span className="dashboard-stat-value">{summary.total_users}</span>
              <span className="dashboard-stat-label">Total Users</span>
            </div>
          </div>

          <div className="dashboard-stat-card dashboard-stat-card--tone-sellers">
            <div className="dashboard-stat-icon dashboard-stat-icon--sellers">
              <Store className="dashboard-stat-icon-svg" aria-hidden="true" />
            </div>
            <div className="dashboard-stat-info">
              <span className="dashboard-stat-value">{summary.approved_sellers}</span>
              <span className="dashboard-stat-label">Active Sellers</span>
            </div>
          </div>

          <div className="dashboard-stat-card dashboard-stat-card--tone-listings">
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
            className="dashboard-stat-card dashboard-stat-card--pending dashboard-stat-card--link dashboard-stat-card--tone-pending"
          >
            <div className="dashboard-stat-icon dashboard-stat-icon--pending">
              <Clock className="dashboard-stat-icon-svg" aria-hidden="true" />
            </div>
            <div className="dashboard-stat-info">
              <span className="dashboard-stat-value">{summary.pending_verifications ?? 0}</span>
              <span className="dashboard-stat-label">Pending Verifications</span>
              <span className="dashboard-stat-sublabel">Seller accounts for review</span>
              <span className="dashboard-stat-pending-action">
                Review queue
                <ArrowRight className="dashboard-stat-pending-arrow" aria-hidden="true" />
              </span>
            </div>
          </Link>

          <div className="dashboard-stat-card dashboard-stat-card--tone-transactions">
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
          <h2 className="dashboard-section-title dashboard-section-title--icon">
            <ChartNoAxesCombined aria-hidden="true" />
            Marketplace Overview
          </h2>

          <div className="dashboard-charts-grid dashboard-charts-grid--flow">
            <div className="dashboard-chart-card">
              <h3 className="dashboard-chart-title dashboard-chart-title--icon">
                <Layers aria-hidden="true" />
                Listings by Status
              </h3>
              {listings.total > 0 ? (
                <ResponsiveContainer width="100%" height={260}>
                  <BarChart
                    data={listingStatusData}
                    layout="vertical"
                    margin={{ top: 10, right: 16, left: 0, bottom: 0 }}
                  >
                    <CartesianGrid strokeDasharray="3 3" stroke={CHART_GRID} horizontal={false} />
                    <XAxis type="number" allowDecimals={false} tick={CHART_TICK} stroke={CHART_AXIS} />
                    <YAxis type="category" dataKey="status" width={82} tick={CHART_TICK} stroke={CHART_AXIS} />
                    <Tooltip formatter={(value) => [String(value ?? 0), 'Listings']} contentStyle={CHART_TOOLTIP_STYLE} />
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
              <h3 className="dashboard-chart-title dashboard-chart-title--icon">
                <ShieldCheck aria-hidden="true" />
                Verification Records by Outcome
              </h3>
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
                    <CartesianGrid strokeDasharray="3 3" stroke={CHART_GRID} />
                    <XAxis dataKey="outcome" tick={CHART_TICK} stroke={CHART_AXIS} />
                    <YAxis allowDecimals={false} tick={CHART_TICK} stroke={CHART_AXIS} />
                    <Tooltip formatter={(value) => [String(value ?? 0), 'Verifications']} contentStyle={CHART_TOOLTIP_STYLE} />
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
                All-time approved and rejected submission records. Applicants may have multiple
                verification records; the pending queue card uses each applicant's latest status.
              </p>
            </div>

            <div className="dashboard-chart-card">
              <h3 className="dashboard-chart-title dashboard-chart-title--icon">
                <TrendingUp aria-hidden="true" />
                Transactions Over Time (Monthly, {now.getFullYear()})
              </h3>
              {transaction_trend.some(item => item.count > 0) ? (
                <ResponsiveContainer width="100%" height={260}>
                  <BarChart data={transaction_trend} margin={{ top: 10, right: 10, left: 0, bottom: 0 }}>
                    <CartesianGrid strokeDasharray="3 3" stroke={CHART_GRID} />
                    <XAxis dataKey="month" tick={CHART_TICK} stroke={CHART_AXIS} />
                    <YAxis allowDecimals={false} tick={CHART_TICK} stroke={CHART_AXIS} />
                    <Tooltip formatter={(value) => [String(value ?? 0), 'Transactions']} contentStyle={CHART_TOOLTIP_STYLE} />
                    <Bar dataKey="count" fill={CHART_BAR} radius={[2, 2, 0, 0]} name="Transactions" />
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
              <h3 className="dashboard-chart-title dashboard-chart-title--icon">
                <Beef aria-hidden="true" />
                Livestock Listings Overview
              </h3>
              {livestock_distribution.length > 0 ? (
                <ResponsiveContainer width="100%" height={260}>
                  <PieChart>
                    <Pie
                      data={livestock_distribution}
                      cx="36%"
                      cy="50%"
                      innerRadius={54}
                      outerRadius={78}
                      paddingAngle={2}
                      dataKey="count"
                      nameKey="type"
                      label={false}
                      labelLine={false}
                    >
                      {livestock_distribution.map((_, index) => (
                        <Cell key={`cell-${index}`} fill={CHART_PIE_COLORS[index % CHART_PIE_COLORS.length]} />
                      ))}
                    </Pie>
                    <text x="36%" y="45%" textAnchor="middle" fill="#64748b" fontSize="11">Total</text>
                    <text x="36%" y="55%" textAnchor="middle" fill="#0a2618" fontSize="22" fontWeight="700">
                      {totalLivestockListings}
                    </text>
                    <text x="36%" y="63%" textAnchor="middle" fill="#64748b" fontSize="10">Listings</text>
                    <Tooltip formatter={(value) => [String(value ?? 0), 'Listings']} contentStyle={CHART_TOOLTIP_STYLE} />
                    <Legend
                      layout="vertical"
                      verticalAlign="middle"
                      align="right"
                      iconType="circle"
                      wrapperStyle={{ width: '40%', right: 0, fontSize: 10, lineHeight: '22px' }}
                    />
                  </PieChart>
                </ResponsiveContainer>
              ) : (
                <div className="dashboard-chart-empty">
                  <p>No livestock listings data available.</p>
                </div>
              )}
              <p className="dashboard-chart-caption">
                Current listings grouped by livestock type (all-time).
              </p>
            </div>
          </div>
        </div>

        <div className="dashboard-section">
          <div className="dashboard-section-header">
            <h2 className="dashboard-section-title dashboard-section-title--icon">
              <Layers aria-hidden="true" />
              Recent Livestock Listings
            </h2>
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
                      <td className="dashboard-activity-date">{formatDateTime(activity.created_at)}</td>
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
    </div>
  );
}
