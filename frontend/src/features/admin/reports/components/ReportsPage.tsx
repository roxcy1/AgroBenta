import { ArrowLeftRight, Package, Store, Users as UsersIcon } from 'lucide-react';
import { useState } from 'react';
import { BarChart, Bar, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer, PieChart, Pie, Cell, Legend, LineChart, Line } from 'recharts';
import { useReports } from '../api/useReports';

const PIE_COLORS = ['#1B5E20', '#2E7D32', '#4CAF50', '#66BB6A', '#81C784', '#A5D6A7', '#C8E6C9'];
const STATUS_COLORS: Record<string, string> = {
  pending: '#F57F17',
  completed: '#2E7D32',
  cancelled: '#C62828',
  active: '#1B5E20',
  sold: '#1565C0',
  draft: '#666666',
  inactive: '#999999',
  submitted: '#1565C0',
  pending_review: '#F57F17',
  approved: '#2E7D32',
  rejected: '#C62828',
};

function formatCurrency(value: number): string {
  if (value === 0) return '₱0';
  return `₱${value.toLocaleString('en-PH', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;
}

function formatNumber(value: number): string {
  return value.toLocaleString('en-PH');
}

export function ReportsPage() {
  const [dateFrom, setDateFrom] = useState('');
  const [dateTo, setDateTo] = useState('');
  const [appliedFilters, setAppliedFilters] = useState<{ date_from?: string; date_to?: string }>({});

  const { data, isLoading, error, refetch } = useReports(appliedFilters);

  const handleApplyFilters = () => {
    const filters: { date_from?: string; date_to?: string } = {};
    if (dateFrom) filters.date_from = dateFrom;
    if (dateTo) filters.date_to = dateTo;
    setAppliedFilters(filters);
  };

  const handleClearFilters = () => {
    setDateFrom('');
    setDateTo('');
    setAppliedFilters({});
  };

  if (isLoading) {
    return (
      <div className="dashboard-content">
        <div className="dashboard-loading">
          <div className="loading-spinner" />
          <span>Loading report data...</span>
        </div>
      </div>
    );
  }

  if (error) {
    return (
      <div className="dashboard-content">
        <div className="dashboard-error">
          <p className="dashboard-error-text">Failed to load report data.</p>
          <button type="button" className="dashboard-retry-button" onClick={() => refetch()}>
            Retry
          </button>
        </div>
      </div>
    );
  }

  if (!data) {
    return (
      <div className="dashboard-content">
        <div className="dashboard-empty">
          <p>No report data available.</p>
        </div>
      </div>
    );
  }

  const { overview, users, listings, transactions, seller_verifications, activities } = data;

  return (
    <div className="dashboard-content">
      <div className="reports-filters">
        <div className="reports-filter-row">
          <div className="reports-filter-group">
            <label className="reports-filter-label" htmlFor="date-from">Date From</label>
            <input
              id="date-from"
              type="date"
              className="reports-filter-input"
              value={dateFrom}
              onChange={(e) => setDateFrom(e.target.value)}
            />
          </div>
          <div className="reports-filter-group">
            <label className="reports-filter-label" htmlFor="date-to">Date To</label>
            <input
              id="date-to"
              type="date"
              className="reports-filter-input"
              value={dateTo}
              onChange={(e) => setDateTo(e.target.value)}
            />
          </div>
          <div className="reports-filter-actions">
            <button type="button" className="dashboard-retry-button" onClick={handleApplyFilters}>
              Apply Filters
            </button>
            {(dateFrom || dateTo) && (
              <button type="button" className="reports-clear-button" onClick={handleClearFilters}>
                Clear
              </button>
            )}
          </div>
        </div>
      </div>

      <div className="dashboard-section">
        <h2 className="dashboard-section-title">Marketplace Overview</h2>
        <div className="dashboard-stats-grid">
          <div className="dashboard-stat-card">
            <div className="dashboard-stat-icon dashboard-stat-icon--users">
              <UsersIcon className="dashboard-stat-icon-svg" aria-hidden="true" />
            </div>
            <div className="dashboard-stat-info">
              <span className="dashboard-stat-value">{formatNumber(overview.total_users)}</span>
              <span className="dashboard-stat-label">Total Users</span>
            </div>
          </div>
          <div className="dashboard-stat-card">
            <div className="dashboard-stat-icon dashboard-stat-icon--sellers">
              <Store className="dashboard-stat-icon-svg" aria-hidden="true" />
            </div>
            <div className="dashboard-stat-info">
              <span className="dashboard-stat-value">{formatNumber(overview.approved_sellers)}</span>
              <span className="dashboard-stat-label">Approved Sellers</span>
            </div>
          </div>
          <div className="dashboard-stat-card">
            <div className="dashboard-stat-icon dashboard-stat-icon--listings">
              <Package className="dashboard-stat-icon-svg" aria-hidden="true" />
            </div>
            <div className="dashboard-stat-info">
              <span className="dashboard-stat-value">{formatNumber(overview.active_listings)}</span>
              <span className="dashboard-stat-label">Active Listings</span>
            </div>
          </div>
          <div className="dashboard-stat-card">
            <div className="dashboard-stat-icon dashboard-stat-icon--transactions">
              <ArrowLeftRight className="dashboard-stat-icon-svg" aria-hidden="true" />
            </div>
            <div className="dashboard-stat-info">
              <span className="dashboard-stat-value">{formatNumber(overview.total_transactions)}</span>
              <span className="dashboard-stat-label">Total Transactions</span>
            </div>
          </div>
        </div>
      </div>

      <div className="dashboard-section">
        <h2 className="dashboard-section-title">Users &amp; Sellers</h2>
        <div className="dashboard-charts-grid">
          <div className="dashboard-chart-card">
            <h3 className="dashboard-chart-title">User Distribution</h3>
            {users.seller_distribution.length > 0 ? (
              <ResponsiveContainer width="100%" height={250}>
                <PieChart>
                  <Pie
                    data={users.seller_distribution}
                    cx="50%"
                    cy="50%"
                    innerRadius={50}
                    outerRadius={85}
                    paddingAngle={2}
                    dataKey="count"
                    nameKey="label"
                    label={({ name, value }: { name?: string; value?: number }) => `${name ?? 'Unknown'}: ${value ?? 0}`}
                    labelLine={false}
                  >
                    {users.seller_distribution.map((_, index) => (
                      <Cell key={`cell-${index}`} fill={PIE_COLORS[index % PIE_COLORS.length]} />
                    ))}
                  </Pie>
                  <Tooltip formatter={(value) => [String(value ?? 0), 'Users']} contentStyle={{ fontSize: 13 }} />
                  <Legend />
                </PieChart>
              </ResponsiveContainer>
            ) : (
              <div className="dashboard-chart-empty"><p>No user data available.</p></div>
            )}
          </div>

          <div className="dashboard-chart-card">
            <h3 className="dashboard-chart-title">User Summary</h3>
            <div className="dashboard-breakdown-list">
              <li>
                <span className="dashboard-breakdown-label">Total Users</span>
                <span className="dashboard-breakdown-value">{formatNumber(users.total)}</span>
              </li>
              <li>
                <span className="dashboard-breakdown-label">Buyers</span>
                <span className="dashboard-breakdown-value">{formatNumber(users.buyers)}</span>
              </li>
              <li>
                <span className="dashboard-breakdown-label">Sellers</span>
                <span className="dashboard-breakdown-value">{formatNumber(users.sellers)}</span>
              </li>
              <li>
                <span className="dashboard-breakdown-label">Admins</span>
                <span className="dashboard-breakdown-value">{formatNumber(users.admins)}</span>
              </li>
            </div>
          </div>
        </div>
      </div>

      <div className="dashboard-section">
        <h2 className="dashboard-section-title">Livestock Listings</h2>
        <div className="dashboard-charts-grid">
          <div className="dashboard-chart-card">
            <h3 className="dashboard-chart-title">Listings by Livestock Type</h3>
            {listings.by_type.length > 0 ? (
              <ResponsiveContainer width="100%" height={250}>
                <BarChart data={listings.by_type} margin={{ top: 10, right: 10, left: 0, bottom: 0 }}>
                  <CartesianGrid strokeDasharray="3 3" stroke="#E0E0E0" />
                  <XAxis dataKey="type" tick={{ fontSize: 12 }} stroke="#666666" />
                  <YAxis tick={{ fontSize: 12 }} stroke="#666666" />
                  <Tooltip formatter={(value) => [String(value ?? 0), 'Listings']} contentStyle={{ fontSize: 13 }} />
                  <Bar dataKey="count" fill="#1B5E20" radius={[2, 2, 0, 0]} name="Listings" />
                </BarChart>
              </ResponsiveContainer>
            ) : (
              <div className="dashboard-chart-empty"><p>No listing data available.</p></div>
            )}
          </div>

          <div className="dashboard-chart-card">
            <h3 className="dashboard-chart-title">Listings by Status</h3>
            {listings.by_status.length > 0 ? (
              <ResponsiveContainer width="100%" height={250}>
                <PieChart>
                  <Pie
                    data={listings.by_status}
                    cx="50%"
                    cy="50%"
                    innerRadius={50}
                    outerRadius={85}
                    paddingAngle={2}
                    dataKey="count"
                    nameKey="status"
                    label={({ name, value }: { name?: string; value?: number }) => `${name ?? 'Unknown'}: ${value ?? 0}`}
                    labelLine={false}
                  >
                    {listings.by_status.map((entry) => (
                      <Cell key={`cell-${entry.status}`} fill={STATUS_COLORS[entry.status] ?? '#666666'} />
                    ))}
                  </Pie>
                  <Tooltip formatter={(value) => [String(value ?? 0), 'Listings']} contentStyle={{ fontSize: 13 }} />
                  <Legend />
                </PieChart>
              </ResponsiveContainer>
            ) : (
              <div className="dashboard-chart-empty"><p>No listing data available.</p></div>
            )}
          </div>
        </div>

        <div className="dashboard-breakdown-grid" style={{ marginTop: '20px' }}>
          <div className="dashboard-breakdown-card">
            <h4 className="dashboard-breakdown-title">Price Statistics</h4>
            <ul className="dashboard-breakdown-list">
              <li>
                <span className="dashboard-breakdown-label">Average Price</span>
                <span className="dashboard-breakdown-value">{formatCurrency(listings.price_stats.avg_price)}</span>
              </li>
              <li>
                <span className="dashboard-breakdown-label">Min Price</span>
                <span className="dashboard-breakdown-value">{formatCurrency(listings.price_stats.min_price)}</span>
              </li>
              <li>
                <span className="dashboard-breakdown-label">Max Price</span>
                <span className="dashboard-breakdown-value">{formatCurrency(listings.price_stats.max_price)}</span>
              </li>
              <li>
                <span className="dashboard-breakdown-label">Total Value</span>
                <span className="dashboard-breakdown-value">{formatCurrency(listings.price_stats.total_value)}</span>
              </li>
            </ul>
          </div>

          <div className="dashboard-breakdown-card">
            <h4 className="dashboard-breakdown-title">Status Breakdown</h4>
            <ul className="dashboard-breakdown-list">
              <li>
                <span className="dashboard-breakdown-label">Active</span>
                <span className="dashboard-breakdown-value">{formatNumber(listings.active)}</span>
              </li>
              <li>
                <span className="dashboard-breakdown-label">Pending</span>
                <span className="dashboard-breakdown-value">{formatNumber(listings.pending)}</span>
              </li>
              <li>
                <span className="dashboard-breakdown-label">Sold</span>
                <span className="dashboard-breakdown-value">{formatNumber(listings.sold)}</span>
              </li>
              <li>
                <span className="dashboard-breakdown-label">Draft</span>
                <span className="dashboard-breakdown-value">{formatNumber(listings.draft)}</span>
              </li>
              <li>
                <span className="dashboard-breakdown-label">Inactive</span>
                <span className="dashboard-breakdown-value">{formatNumber(listings.inactive)}</span>
              </li>
            </ul>
          </div>

          <div className="dashboard-breakdown-card">
            <h4 className="dashboard-breakdown-title">Quick Stats</h4>
            <ul className="dashboard-breakdown-list">
              <li>
                <span className="dashboard-breakdown-label">Total Listings</span>
                <span className="dashboard-breakdown-value">{formatNumber(listings.total)}</span>
              </li>
            </ul>
          </div>
        </div>
      </div>

      <div className="dashboard-section">
        <h2 className="dashboard-section-title">Transactions</h2>
        <div className="dashboard-charts-grid">
          <div className="dashboard-chart-card">
            <h3 className="dashboard-chart-title">Transaction Trend</h3>
            {transactions.trend.length > 0 ? (
              <ResponsiveContainer width="100%" height={250}>
                <LineChart data={transactions.trend} margin={{ top: 10, right: 10, left: 0, bottom: 0 }}>
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
                  <Line type="monotone" dataKey="count" stroke="#1B5E20" strokeWidth={2} dot={{ r: 3 }} name="Transactions" />
                </LineChart>
              </ResponsiveContainer>
            ) : (
              <div className="dashboard-chart-empty"><p>No transaction data available.</p></div>
            )}
          </div>

          <div className="dashboard-chart-card">
            <h3 className="dashboard-chart-title">Transactions by Status</h3>
            {transactions.by_status.length > 0 ? (
              <ResponsiveContainer width="100%" height={250}>
                <PieChart>
                  <Pie
                    data={transactions.by_status}
                    cx="50%"
                    cy="50%"
                    innerRadius={50}
                    outerRadius={85}
                    paddingAngle={2}
                    dataKey="count"
                    nameKey="status"
                    label={({ name, value }: { name?: string; value?: number }) => `${name ?? 'Unknown'}: ${value ?? 0}`}
                    labelLine={false}
                  >
                    {transactions.by_status.map((entry) => (
                      <Cell key={`cell-${entry.status}`} fill={STATUS_COLORS[entry.status] ?? '#666666'} />
                    ))}
                  </Pie>
                  <Tooltip formatter={(value) => [String(value ?? 0), 'Transactions']} contentStyle={{ fontSize: 13 }} />
                  <Legend />
                </PieChart>
              </ResponsiveContainer>
            ) : (
              <div className="dashboard-chart-empty"><p>No transaction data available.</p></div>
            )}
          </div>
        </div>

        <div className="dashboard-breakdown-grid" style={{ marginTop: '20px' }}>
          <div className="dashboard-breakdown-card">
            <h4 className="dashboard-breakdown-title">Revenue Summary</h4>
            <ul className="dashboard-breakdown-list">
              <li>
                <span className="dashboard-breakdown-label">Total Revenue</span>
                <span className="dashboard-breakdown-value">{formatCurrency(transactions.total_revenue)}</span>
              </li>
              <li>
                <span className="dashboard-breakdown-label">Average Amount</span>
                <span className="dashboard-breakdown-value">{formatCurrency(transactions.avg_amount)}</span>
              </li>
            </ul>
          </div>

          <div className="dashboard-breakdown-card">
            <h4 className="dashboard-breakdown-title">Transaction Status</h4>
            <ul className="dashboard-breakdown-list">
              <li>
                <span className="dashboard-breakdown-label">Pending</span>
                <span className="dashboard-breakdown-value">{formatNumber(transactions.pending)}</span>
              </li>
              <li>
                <span className="dashboard-breakdown-label">Completed</span>
                <span className="dashboard-breakdown-value">{formatNumber(transactions.completed)}</span>
              </li>
              <li>
                <span className="dashboard-breakdown-label">Cancelled</span>
                <span className="dashboard-breakdown-value">{formatNumber(transactions.cancelled)}</span>
              </li>
            </ul>
          </div>

          <div className="dashboard-breakdown-card">
            <h4 className="dashboard-breakdown-title">Transactions by Livestock</h4>
            <ul className="dashboard-breakdown-list">
              {transactions.by_livestock.length > 0 ? (
                transactions.by_livestock.map((item) => (
                  <li key={item.livestock_type}>
                    <span className="dashboard-breakdown-label">{item.livestock_type}</span>
                    <span className="dashboard-breakdown-value">{formatNumber(item.count)} ({formatCurrency(item.total_amount)})</span>
                  </li>
                ))
              ) : (
                <li>
                  <span className="dashboard-breakdown-label">No data</span>
                  <span className="dashboard-breakdown-value">—</span>
                </li>
              )}
            </ul>
          </div>
        </div>
      </div>

      <div className="dashboard-section">
        <h2 className="dashboard-section-title">Seller Verification</h2>
        <div className="dashboard-charts-grid">
          <div className="dashboard-chart-card">
            <h3 className="dashboard-chart-title">Verification Trend</h3>
            {seller_verifications.submission_trend.length > 0 ? (
              <ResponsiveContainer width="100%" height={250}>
                <BarChart data={seller_verifications.submission_trend} margin={{ top: 10, right: 10, left: 0, bottom: 0 }}>
                  <CartesianGrid strokeDasharray="3 3" stroke="#E0E0E0" />
                  <XAxis dataKey="month" tick={{ fontSize: 12 }} stroke="#666666" />
                  <YAxis tick={{ fontSize: 12 }} stroke="#666666" />
                  <Tooltip formatter={(value) => [String(value ?? 0), 'Submissions']} contentStyle={{ fontSize: 13 }} />
                  <Bar dataKey="count" fill="#6A1B9A" radius={[2, 2, 0, 0]} name="Submissions" />
                </BarChart>
              </ResponsiveContainer>
            ) : (
              <div className="dashboard-chart-empty"><p>No verification data available.</p></div>
            )}
          </div>

          <div className="dashboard-chart-card">
            <h3 className="dashboard-chart-title">Status Distribution</h3>
            {seller_verifications.status_distribution.length > 0 ? (
              <ResponsiveContainer width="100%" height={250}>
                <PieChart>
                  <Pie
                    data={seller_verifications.status_distribution}
                    cx="50%"
                    cy="50%"
                    innerRadius={50}
                    outerRadius={85}
                    paddingAngle={2}
                    dataKey="count"
                    nameKey="status"
                    label={({ name, value }: { name?: string; value?: number }) => `${name ?? 'Unknown'}: ${value ?? 0}`}
                    labelLine={false}
                  >
                    {seller_verifications.status_distribution.map((entry) => (
                      <Cell key={`cell-${entry.status}`} fill={STATUS_COLORS[entry.status] ?? '#666666'} />
                    ))}
                  </Pie>
                  <Tooltip formatter={(value) => [String(value ?? 0), 'Verifications']} contentStyle={{ fontSize: 13 }} />
                  <Legend />
                </PieChart>
              </ResponsiveContainer>
            ) : (
              <div className="dashboard-chart-empty"><p>No verification data available.</p></div>
            )}
          </div>
        </div>

        <div className="dashboard-breakdown-grid" style={{ marginTop: '20px' }}>
          <div className="dashboard-breakdown-card">
            <h4 className="dashboard-breakdown-title">Verification Summary</h4>
            <ul className="dashboard-breakdown-list">
              <li>
                <span className="dashboard-breakdown-label">Total Submissions</span>
                <span className="dashboard-breakdown-value">{formatNumber(seller_verifications.total)}</span>
              </li>
              <li>
                <span className="dashboard-breakdown-label">Submitted</span>
                <span className="dashboard-breakdown-value">{formatNumber(seller_verifications.submitted)}</span>
              </li>
              <li>
                <span className="dashboard-breakdown-label">Pending Review</span>
                <span className="dashboard-breakdown-value">{formatNumber(seller_verifications.pending_review)}</span>
              </li>
              <li>
                <span className="dashboard-breakdown-label">Approved</span>
                <span className="dashboard-breakdown-value">{formatNumber(seller_verifications.approved)}</span>
              </li>
              <li>
                <span className="dashboard-breakdown-label">Rejected</span>
                <span className="dashboard-breakdown-value">{formatNumber(seller_verifications.rejected)}</span>
              </li>
            </ul>
          </div>

          <div className="dashboard-breakdown-card">
            <h4 className="dashboard-breakdown-title">Approval Rate</h4>
            <ul className="dashboard-breakdown-list">
              <li>
                <span className="dashboard-breakdown-label">Approved</span>
                <span className="dashboard-breakdown-value">
                  {seller_verifications.total > 0
                    ? `${((seller_verifications.approved / seller_verifications.total) * 100).toFixed(1)}%`
                    : '—'}
                </span>
              </li>
              <li>
                <span className="dashboard-breakdown-label">Rejected</span>
                <span className="dashboard-breakdown-value">
                  {seller_verifications.total > 0
                    ? `${((seller_verifications.rejected / seller_verifications.total) * 100).toFixed(1)}%`
                    : '—'}
                </span>
              </li>
            </ul>
          </div>
        </div>
      </div>

      <div className="dashboard-section">
        <h2 className="dashboard-section-title">Activities</h2>
        <div className="dashboard-charts-grid">
          <div className="dashboard-chart-card">
            <h3 className="dashboard-chart-title">Activity Trend</h3>
            {activities.trend.length > 0 ? (
              <ResponsiveContainer width="100%" height={250}>
                <LineChart data={activities.trend} margin={{ top: 10, right: 10, left: 0, bottom: 0 }}>
                  <CartesianGrid strokeDasharray="3 3" stroke="#E0E0E0" />
                  <XAxis dataKey="month" tick={{ fontSize: 12 }} stroke="#666666" />
                  <YAxis tick={{ fontSize: 12 }} stroke="#666666" />
                  <Tooltip formatter={(value) => [String(value ?? 0), 'Activities']} contentStyle={{ fontSize: 13 }} />
                  <Line type="monotone" dataKey="count" stroke="#4CAF50" strokeWidth={2} dot={{ r: 3 }} name="Activities" />
                </LineChart>
              </ResponsiveContainer>
            ) : (
              <div className="dashboard-chart-empty"><p>No activity data available.</p></div>
            )}
          </div>

          <div className="dashboard-chart-card">
            <h3 className="dashboard-chart-title">Activities by Action</h3>
            {activities.by_action.length > 0 ? (
              <ResponsiveContainer width="100%" height={250}>
                <BarChart data={activities.by_action.slice(0, 8)} margin={{ top: 10, right: 10, left: 0, bottom: 0 }}>
                  <CartesianGrid strokeDasharray="3 3" stroke="#E0E0E0" />
                  <XAxis dataKey="action" tick={{ fontSize: 11 }} stroke="#666666" angle={-45} textAnchor="end" height={60} />
                  <YAxis tick={{ fontSize: 12 }} stroke="#666666" />
                  <Tooltip formatter={(value) => [String(value ?? 0), 'Count']} contentStyle={{ fontSize: 13 }} />
                  <Bar dataKey="count" fill="#4CAF50" radius={[2, 2, 0, 0]} name="Count" />
                </BarChart>
              </ResponsiveContainer>
            ) : (
              <div className="dashboard-chart-empty"><p>No activity data available.</p></div>
            )}
          </div>
        </div>

        <div className="dashboard-breakdown-grid" style={{ marginTop: '20px' }}>
          <div className="dashboard-breakdown-card">
            <h4 className="dashboard-breakdown-title">Activity Summary</h4>
            <ul className="dashboard-breakdown-list">
              <li>
                <span className="dashboard-breakdown-label">Total Activities</span>
                <span className="dashboard-breakdown-value">{formatNumber(activities.total)}</span>
              </li>
            </ul>
          </div>

          <div className="dashboard-breakdown-card" style={{ gridColumn: 'span 2' }}>
            <h4 className="dashboard-breakdown-title">Top Users by Activity</h4>
            {activities.by_user.length > 0 ? (
              <ul className="dashboard-breakdown-list">
                {activities.by_user.slice(0, 5).map((item) => (
                  <li key={item.user_id ?? 'system'}>
                    <span className="dashboard-breakdown-label">{item.user_name}</span>
                    <span className="dashboard-breakdown-value">{formatNumber(item.count)} activities</span>
                  </li>
                ))}
              </ul>
            ) : (
              <ul className="dashboard-breakdown-list">
                <li>
                  <span className="dashboard-breakdown-label">No data</span>
                  <span className="dashboard-breakdown-value">—</span>
                </li>
              </ul>
            )}
          </div>
        </div>
      </div>
    </div>
  );
}
