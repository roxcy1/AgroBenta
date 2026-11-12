import { ArrowLeftRight, CalendarDays, Download, Package, Store, Users as UsersIcon } from 'lucide-react';
import { useState } from 'react';
import { BarChart, Bar, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer, PieChart, Pie, Cell, Legend, LineChart, Line } from 'recharts';
import { useReports } from '../api/useReports';
import { buildReportsCsv, buildReportsFilename } from '../csv';
import { livestockTypeLabel, useLivestockTypes } from '../../livestock/api/useLivestockTypes';
import { formatNumber, formatPeso } from '../../../../lib/format';
import { downloadCsv } from '../../../../lib/csv';
import { statusChartColor } from '../../../../lib/status';
import { CHART_AXIS, CHART_BAR, CHART_BAR_SECONDARY, CHART_GRID, CHART_LINE_ACCENT, CHART_PIE_COLORS, CHART_TICK_SMALL, CHART_TOOLTIP_STYLE } from '../../../../lib/chartTheme';

const REPORT_CHART_HEIGHT = 230;
const REPORT_CHART_TICK = { ...CHART_TICK_SMALL, fill: '#718078' };
const REPORT_CHART_TOOLTIP_STYLE = {
  ...CHART_TOOLTIP_STYLE,
  backgroundColor: '#fff',
  border: '1px solid #e2e8f0',
  borderRadius: 9,
  boxShadow: '0 8px 20px rgba(19, 48, 30, 0.12)',
};

export function ReportsPage() {
  const [dateFrom, setDateFrom] = useState('');
  const [dateTo, setDateTo] = useState('');
  const [appliedFilters, setAppliedFilters] = useState<{ date_from?: string; date_to?: string }>({});
  const [validationError, setValidationError] = useState('');

  const { data, isLoading, isFetching, error, refetch } = useReports(appliedFilters);
  const { data: livestockTypes } = useLivestockTypes();

  const today = (() => {
    const now = new Date();
    return `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}-${String(now.getDate()).padStart(2, '0')}`;
  })();

  const handleApplyFilters = () => {
    if (dateFrom && dateTo && dateTo < dateFrom) {
      setValidationError('Date To must be on or after Date From.');
      return;
    }
    if (dateFrom && dateFrom > today) {
      setValidationError('Date From cannot be in the future.');
      return;
    }

    setValidationError('');

    const filters: { date_from?: string; date_to?: string } = {};
    if (dateFrom) filters.date_from = dateFrom;
    if (dateTo) filters.date_to = dateTo;
    setAppliedFilters(filters);
  };

  const handleClearFilters = () => {
    setDateFrom('');
    setDateTo('');
    setValidationError('');
    setAppliedFilters({});
  };

  const handleExportCsv = () => {
    if (!data || isLoading || isFetching || error) return;

    downloadCsv(buildReportsFilename(appliedFilters), buildReportsCsv(data, appliedFilters));
  };

  const hasActiveFilter = Boolean(appliedFilters.date_from || appliedFilters.date_to);
  const appliedRangeText = appliedFilters.date_from && appliedFilters.date_to
    ? `Showing ${appliedFilters.date_from} to ${appliedFilters.date_to}`
    : appliedFilters.date_from
      ? `Showing from ${appliedFilters.date_from}`
      : appliedFilters.date_to
        ? `Showing up to ${appliedFilters.date_to}`
        : 'Showing all-time data';
  const reportRangeLabel = hasActiveFilter ? 'the selected date range' : 'all-time';

  const filtersPanel = (
    <div className="reports-filters">
      <div className="reports-filters-heading">
        <span className="reports-filters-icon">
          <CalendarDays aria-hidden="true" />
        </span>
        <div>
          <h2>Report filters</h2>
          <p>Choose an optional date range for supported reports.</p>
        </div>
      </div>
      <div className="reports-filter-row">
        <div className="reports-filter-group">
          <label className="reports-filter-label" htmlFor="date-from">Date From</label>
          <input
            id="date-from"
            type="date"
            className="reports-filter-input"
            value={dateFrom}
            max={today}
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
            min={dateFrom || undefined}
            onChange={(e) => setDateTo(e.target.value)}
          />
        </div>
        <div className="reports-filter-actions">
          <button type="button" className="dashboard-retry-button" onClick={handleApplyFilters}>
            Apply Filters
          </button>
          {(dateFrom || dateTo || hasActiveFilter) && (
            <button type="button" className="reports-clear-button" onClick={handleClearFilters}>
              Clear
            </button>
          )}
          <button
            type="button"
            className="reports-clear-button reports-export-button"
            onClick={handleExportCsv}
            disabled={!data || isLoading || isFetching || Boolean(error)}
            aria-label="Export report data as CSV"
          >
            <Download aria-hidden="true" />
            Export CSV
          </button>
        </div>
      </div>

      {validationError && (
        <p className="reports-filter-error" role="alert">{validationError}</p>
      )}

      <div className="reports-filter-meta">
        <span className="reports-active-filters">{appliedRangeText}</span>
        {isFetching && data && <span className="reports-updating">Updating…</span>}
      </div>

      <p className="reports-coverage-note">
        Date range applies to transactions, seller verifications, activities, listing
        totals and price statistics, and registration trends. User totals and listing
        status counts are all-time.
      </p>
    </div>
  );

  if (isLoading && !data) {
    return (
      <div className="dashboard-content">
        {filtersPanel}
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
        {filtersPanel}
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
        {filtersPanel}
        <div className="dashboard-empty">
          <p>No report data available.</p>
        </div>
      </div>
    );
  }

  const { overview, users, listings, transactions, seller_verifications, activities } = data;

  return (
    <div className="dashboard-content">
      {filtersPanel}

      <div className="dashboard-section">
        <h2 className="dashboard-section-title">Marketplace Overview</h2>
        <div className="dashboard-stats-grid">
          <div className="dashboard-stat-card dashboard-stat-card--tone-users">
            <div className="dashboard-stat-icon dashboard-stat-icon--users">
              <UsersIcon className="dashboard-stat-icon-svg" aria-hidden="true" />
            </div>
            <div className="dashboard-stat-info">
              <span className="dashboard-stat-value">{formatNumber(overview.total_users)}</span>
              <span className="dashboard-stat-label">Total Users</span>
              <span className="dashboard-stat-sublabel">All-time</span>
            </div>
          </div>
          <div className="dashboard-stat-card dashboard-stat-card--tone-sellers">
            <div className="dashboard-stat-icon dashboard-stat-icon--sellers">
              <Store className="dashboard-stat-icon-svg" aria-hidden="true" />
            </div>
            <div className="dashboard-stat-info">
              <span className="dashboard-stat-value">{formatNumber(overview.approved_sellers)}</span>
              <span className="dashboard-stat-label">Approved Sellers</span>
              <span className="dashboard-stat-sublabel">All-time</span>
            </div>
          </div>
          <div className="dashboard-stat-card dashboard-stat-card--tone-listings">
            <div className="dashboard-stat-icon dashboard-stat-icon--listings">
              <Package className="dashboard-stat-icon-svg" aria-hidden="true" />
            </div>
            <div className="dashboard-stat-info">
              <span className="dashboard-stat-value">{formatNumber(overview.active_listings)}</span>
              <span className="dashboard-stat-label">Active Listings</span>
              <span className="dashboard-stat-sublabel">All-time</span>
            </div>
          </div>
          <div className="dashboard-stat-card dashboard-stat-card--tone-transactions">
            <div className="dashboard-stat-icon dashboard-stat-icon--transactions">
              <ArrowLeftRight className="dashboard-stat-icon-svg" aria-hidden="true" />
            </div>
            <div className="dashboard-stat-info">
              <span className="dashboard-stat-value">{formatNumber(overview.total_transactions)}</span>
              <span className="dashboard-stat-label">Transactions</span>
              <span className="dashboard-stat-sublabel">
                {hasActiveFilter ? 'Selected period' : 'All-time'}
              </span>
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
              <ResponsiveContainer width="100%" height={REPORT_CHART_HEIGHT}>
                <PieChart>
                  <Pie
                    data={users.seller_distribution}
                    cx="50%"
                    cy="50%"
                    innerRadius={50}
                    outerRadius={78}
                    paddingAngle={2}
                    dataKey="count"
                    nameKey="label"
                    label={({ name, value }: { name?: string; value?: number }) => `${name ?? 'Unknown'}: ${value ?? 0}`}
                    labelLine={false}
                  >
                    {users.seller_distribution.map((_, index) => (
                      <Cell key={`cell-${index}`} fill={CHART_PIE_COLORS[index % CHART_PIE_COLORS.length]} />
                    ))}
                  </Pie>
                  <Tooltip formatter={(value) => [String(value ?? 0), 'Users']} contentStyle={REPORT_CHART_TOOLTIP_STYLE} />
                  <Legend wrapperStyle={{ fontSize: 11 }} />
                </PieChart>
              </ResponsiveContainer>
            ) : (
              <div className="dashboard-chart-empty"><p>No user data available.</p></div>
            )}
            <p className="dashboard-chart-caption">Current buyer and seller capability counts (all-time).</p>
          </div>

          <div className="dashboard-chart-card">
            <h3 className="dashboard-chart-title">User Summary</h3>
            <ul className="dashboard-breakdown-list">
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
            </ul>
          </div>
        </div>
      </div>

      <div className="dashboard-section">
        <h2 className="dashboard-section-title">Livestock Listings</h2>
        <div className="dashboard-charts-grid">
          <div className="dashboard-chart-card">
            <h3 className="dashboard-chart-title">Listings by Livestock Type</h3>
            {listings.by_type.length > 0 ? (
              <ResponsiveContainer width="100%" height={REPORT_CHART_HEIGHT}>
                <BarChart data={listings.by_type} margin={{ top: 10, right: 10, left: 0, bottom: 0 }}>
                  <CartesianGrid strokeDasharray="3 4" stroke={CHART_GRID} strokeOpacity={0.65} />
                  <XAxis dataKey="type" tick={REPORT_CHART_TICK} stroke={CHART_AXIS} />
                  <YAxis tick={REPORT_CHART_TICK} stroke={CHART_AXIS} />
                  <Tooltip formatter={(value) => [String(value ?? 0), 'Listings']} contentStyle={REPORT_CHART_TOOLTIP_STYLE} />
                  <Bar dataKey="count" barSize={24} radius={[6, 6, 0, 0]} name="Listings">
                    {listings.by_type.map((_, index) => (
                      <Cell key={`livestock-type-${index}`} fill={CHART_PIE_COLORS[index % CHART_PIE_COLORS.length]} />
                    ))}
                  </Bar>
                </BarChart>
              </ResponsiveContainer>
            ) : (
              <div className="dashboard-chart-empty"><p>No listing data available.</p></div>
            )}
            <p className="dashboard-chart-caption">Listing counts by livestock type for {reportRangeLabel}.</p>
          </div>

          <div className="dashboard-chart-card">
            <h3 className="dashboard-chart-title">Listings by Status</h3>
            {listings.by_status.length > 0 ? (
              <ResponsiveContainer width="100%" height={REPORT_CHART_HEIGHT}>
                <PieChart>
                  <Pie
                    data={listings.by_status}
                    cx="50%"
                    cy="50%"
                    innerRadius={50}
                    outerRadius={78}
                    paddingAngle={2}
                    dataKey="count"
                    nameKey="status"
                    label={({ name, value }: { name?: string; value?: number }) => `${name ?? 'Unknown'}: ${value ?? 0}`}
                    labelLine={false}
                  >
                    {listings.by_status.map((entry) => (
                      <Cell key={`cell-${entry.status}`} fill={statusChartColor(entry.status)} />
                    ))}
                  </Pie>
                  <Tooltip formatter={(value) => [String(value ?? 0), 'Listings']} contentStyle={REPORT_CHART_TOOLTIP_STYLE} />
                  <Legend wrapperStyle={{ fontSize: 11 }} />
                </PieChart>
              </ResponsiveContainer>
            ) : (
              <div className="dashboard-chart-empty"><p>No listing data available.</p></div>
            )}
            <p className="dashboard-chart-caption">Current listing status totals (all-time).</p>
          </div>
        </div>

        <div className="dashboard-breakdown-grid dashboard-breakdown-grid--reports">
          <div className="dashboard-breakdown-card">
            <h4 className="dashboard-breakdown-title">Price Statistics</h4>
            <ul className="dashboard-breakdown-list">
              <li>
                <span className="dashboard-breakdown-label">Average Price</span>
                <span className="dashboard-breakdown-value">{formatPeso(listings.price_stats.avg_price)}</span>
              </li>
              <li>
                <span className="dashboard-breakdown-label">Min Price</span>
                <span className="dashboard-breakdown-value">{formatPeso(listings.price_stats.min_price)}</span>
              </li>
              <li>
                <span className="dashboard-breakdown-label">Max Price</span>
                <span className="dashboard-breakdown-value">{formatPeso(listings.price_stats.max_price)}</span>
              </li>
              <li>
                <span className="dashboard-breakdown-label">Total Value</span>
                <span className="dashboard-breakdown-value">{formatPeso(listings.price_stats.total_value)}</span>
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
              <ResponsiveContainer width="100%" height={REPORT_CHART_HEIGHT}>
                <LineChart data={transactions.trend} margin={{ top: 10, right: 10, left: 0, bottom: 0 }}>
                  <CartesianGrid strokeDasharray="3 4" stroke={CHART_GRID} strokeOpacity={0.65} />
                  <XAxis dataKey="month" tick={REPORT_CHART_TICK} stroke={CHART_AXIS} />
                  <YAxis tick={REPORT_CHART_TICK} stroke={CHART_AXIS} />
                  <Tooltip
                    formatter={(value) => [String(value ?? 0), 'Transactions']}
                    contentStyle={REPORT_CHART_TOOLTIP_STYLE}
                  />
                  <Line type="monotone" dataKey="count" stroke={CHART_BAR} strokeWidth={2.5} dot={{ r: 3, fill: CHART_BAR }} activeDot={{ r: 5 }} name="Transactions" />
                </LineChart>
              </ResponsiveContainer>
            ) : (
              <div className="dashboard-chart-empty"><p>No transaction data available.</p></div>
            )}
            <p className="dashboard-chart-caption">Monthly transaction counts for {reportRangeLabel}.</p>
          </div>

          <div className="dashboard-chart-card">
            <h3 className="dashboard-chart-title">Transactions by Status</h3>
            {transactions.by_status.length > 0 ? (
              <ResponsiveContainer width="100%" height={REPORT_CHART_HEIGHT}>
                <PieChart>
                  <Pie
                    data={transactions.by_status}
                    cx="50%"
                    cy="50%"
                    innerRadius={50}
                    outerRadius={78}
                    paddingAngle={2}
                    dataKey="count"
                    nameKey="status"
                    label={({ name, value }: { name?: string; value?: number }) => `${name ?? 'Unknown'}: ${value ?? 0}`}
                    labelLine={false}
                  >
                    {transactions.by_status.map((entry) => (
                      <Cell key={`cell-${entry.status}`} fill={statusChartColor(entry.status)} />
                    ))}
                  </Pie>
                  <Tooltip formatter={(value) => [String(value ?? 0), 'Transactions']} contentStyle={REPORT_CHART_TOOLTIP_STYLE} />
                  <Legend wrapperStyle={{ fontSize: 11 }} />
                </PieChart>
              </ResponsiveContainer>
            ) : (
              <div className="dashboard-chart-empty"><p>No transaction data available.</p></div>
            )}
            <p className="dashboard-chart-caption">Transaction status counts for {reportRangeLabel}.</p>
          </div>
        </div>

        <div className="dashboard-breakdown-grid dashboard-breakdown-grid--reports">
          <div className="dashboard-breakdown-card">
            <h4 className="dashboard-breakdown-title">Transaction Amounts</h4>
            <ul className="dashboard-breakdown-list">
              <li>
                <span className="dashboard-breakdown-label">Recorded Arrangement Value</span>
                <span className="dashboard-breakdown-value">{formatPeso(transactions.total_revenue)}</span>
              </li>
              <li>
                <span className="dashboard-breakdown-label">Average Amount</span>
                <span className="dashboard-breakdown-value">{formatPeso(transactions.avg_amount)}</span>
              </li>
            </ul>
            <p className="dashboard-chart-caption">
              Recorded arrangement values, not revenue, earnings, or payments processed by AgroBenta.
            </p>
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
                    <span className="dashboard-breakdown-label">{livestockTypeLabel(item.livestock_type, livestockTypes)}</span>
                    <span className="dashboard-breakdown-value">{formatNumber(item.count)} ({formatPeso(item.total_amount)})</span>
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
              <ResponsiveContainer width="100%" height={REPORT_CHART_HEIGHT}>
                <BarChart data={seller_verifications.submission_trend} margin={{ top: 10, right: 10, left: 0, bottom: 0 }}>
                  <CartesianGrid strokeDasharray="3 4" stroke={CHART_GRID} strokeOpacity={0.65} />
                  <XAxis dataKey="month" tick={REPORT_CHART_TICK} stroke={CHART_AXIS} />
                  <YAxis tick={REPORT_CHART_TICK} stroke={CHART_AXIS} />
                  <Tooltip formatter={(value) => [String(value ?? 0), 'Submissions']} contentStyle={REPORT_CHART_TOOLTIP_STYLE} />
                  <Bar dataKey="count" fill={CHART_BAR_SECONDARY} barSize={22} radius={[6, 6, 0, 0]} name="Submissions" />
                </BarChart>
              </ResponsiveContainer>
            ) : (
              <div className="dashboard-chart-empty"><p>No verification data available.</p></div>
            )}
          </div>

          <div className="dashboard-chart-card">
            <h3 className="dashboard-chart-title">Verification Records by Status</h3>
            {seller_verifications.status_distribution.length > 0 ? (
              <ResponsiveContainer width="100%" height={REPORT_CHART_HEIGHT}>
                <PieChart>
                  <Pie
                    data={seller_verifications.status_distribution}
                    cx="50%"
                    cy="50%"
                    innerRadius={50}
                    outerRadius={78}
                    paddingAngle={2}
                    dataKey="count"
                    nameKey="status"
                    label={({ name, value }: { name?: string; value?: number }) => `${name ?? 'Unknown'}: ${value ?? 0}`}
                    labelLine={false}
                  >
                    {seller_verifications.status_distribution.map((entry) => (
                      <Cell key={`cell-${entry.status}`} fill={statusChartColor(entry.status)} />
                    ))}
                  </Pie>
                  <Tooltip formatter={(value) => [String(value ?? 0), 'Verifications']} contentStyle={REPORT_CHART_TOOLTIP_STYLE} />
                  <Legend wrapperStyle={{ fontSize: 11 }} />
                </PieChart>
              </ResponsiveContainer>
            ) : (
              <div className="dashboard-chart-empty"><p>No verification data available.</p></div>
            )}
            <p className="dashboard-chart-caption">
              Submission records by status for {reportRangeLabel}; applicants may have multiple records over time.
            </p>
          </div>
        </div>

        <div className="dashboard-breakdown-grid dashboard-breakdown-grid--reports">
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
            <p className="dashboard-chart-caption">
              Counts are submission records; one applicant may have multiple records over time.
            </p>
          </div>

          <div className="dashboard-breakdown-card">
            <h4 className="dashboard-breakdown-title">Decision Share of All Records</h4>
            <ul className="dashboard-breakdown-list">
              <li>
                <span className="dashboard-breakdown-label">Approved / all records</span>
                <span className="dashboard-breakdown-value">
                  {seller_verifications.total > 0
                    ? `${((seller_verifications.approved / seller_verifications.total) * 100).toFixed(1)}%`
                    : '—'}
                </span>
              </li>
              <li>
                <span className="dashboard-breakdown-label">Rejected / all records</span>
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
              <ResponsiveContainer width="100%" height={REPORT_CHART_HEIGHT}>
                <LineChart data={activities.trend} margin={{ top: 10, right: 10, left: 0, bottom: 0 }}>
                  <CartesianGrid strokeDasharray="3 4" stroke={CHART_GRID} strokeOpacity={0.65} />
                  <XAxis dataKey="month" tick={REPORT_CHART_TICK} stroke={CHART_AXIS} />
                  <YAxis tick={REPORT_CHART_TICK} stroke={CHART_AXIS} />
                  <Tooltip formatter={(value) => [String(value ?? 0), 'Activities']} contentStyle={REPORT_CHART_TOOLTIP_STYLE} />
                  <Line type="monotone" dataKey="count" stroke={CHART_LINE_ACCENT} strokeWidth={2.5} dot={{ r: 3, fill: CHART_LINE_ACCENT }} activeDot={{ r: 5 }} name="Activities" />
                </LineChart>
              </ResponsiveContainer>
            ) : (
              <div className="dashboard-chart-empty"><p>No activity data available.</p></div>
            )}
            <p className="dashboard-chart-caption">Recorded activity counts for {reportRangeLabel}.</p>
          </div>

          <div className="dashboard-chart-card">
            <h3 className="dashboard-chart-title">Activities by Action</h3>
            {activities.by_action.length > 0 ? (
              <ResponsiveContainer width="100%" height={REPORT_CHART_HEIGHT}>
                <BarChart data={activities.by_action.slice(0, 8)} margin={{ top: 10, right: 10, left: 0, bottom: 0 }}>
                  <CartesianGrid strokeDasharray="3 4" stroke={CHART_GRID} strokeOpacity={0.65} />
                  <XAxis dataKey="action" tick={REPORT_CHART_TICK} stroke={CHART_AXIS} angle={-45} textAnchor="end" height={60} />
                  <YAxis tick={REPORT_CHART_TICK} stroke={CHART_AXIS} />
                  <Tooltip formatter={(value) => [String(value ?? 0), 'Count']} contentStyle={REPORT_CHART_TOOLTIP_STYLE} />
                  <Bar dataKey="count" fill={CHART_LINE_ACCENT} barSize={22} radius={[6, 6, 0, 0]} name="Count" />
                </BarChart>
              </ResponsiveContainer>
            ) : (
              <div className="dashboard-chart-empty"><p>No activity data available.</p></div>
            )}
            <p className="dashboard-chart-caption">Recorded activity events grouped by action for {reportRangeLabel}.</p>
          </div>
        </div>

        <div className="dashboard-breakdown-grid dashboard-breakdown-grid--reports">
          <div className="dashboard-breakdown-card">
            <h4 className="dashboard-breakdown-title">Activity Summary</h4>
            <ul className="dashboard-breakdown-list">
              <li>
                <span className="dashboard-breakdown-label">Total Activities</span>
                <span className="dashboard-breakdown-value">{formatNumber(activities.total)}</span>
              </li>
            </ul>
          </div>

          <div className="dashboard-breakdown-card dashboard-breakdown-card--wide">
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
