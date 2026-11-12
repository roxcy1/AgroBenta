import { buildCsvContent, type CsvField } from '../../../lib/csv';
import type { ReportData, ReportParams } from './api/useReports';

const CSV_HEADERS = ['Section', 'Metric', 'Period', 'Value'] as const;

function reportPeriod(params: ReportParams): string {
  if (params.date_from && params.date_to) {
    return `${params.date_from} through ${params.date_to}`;
  }
  if (params.date_from) return `From ${params.date_from}`;
  if (params.date_to) return `Through ${params.date_to}`;
  return 'All-time';
}

export function buildReportsCsv(data: ReportData, params: ReportParams = {}): string {
  const filteredPeriod = reportPeriod(params);
  const rows: CsvField[][] = [
    [...CSV_HEADERS],
    ['Report', 'Applied date range', filteredPeriod, ''],
    [
      'Report',
      'Coverage',
      '',
      'Date range applies to transactions, seller verifications, activities, listing totals and price statistics, and registration trends. User totals and listing status counts are all-time.',
    ],
  ];
  const add = (section: string, metric: string, value: CsvField, period = 'All-time') => {
    rows.push([section, metric, period, value]);
  };

  add('Overview', 'Total users', data.overview.total_users);
  add('Overview', 'Buyer accounts', data.overview.buyer_accounts);
  add('Overview', 'Approved sellers', data.overview.approved_sellers);
  add('Overview', 'Total listings', data.overview.total_listings);
  add('Overview', 'Active listings', data.overview.active_listings);
  add('Overview', 'Sold listings', data.overview.sold_listings);
  add('Overview', 'Pending listings', data.overview.pending_listings);
  add('Overview', 'Total transactions', data.overview.total_transactions, filteredPeriod);
  add('Overview', 'Pending transactions', data.overview.pending_transactions, filteredPeriod);
  add('Overview', 'Completed transactions', data.overview.completed_transactions, filteredPeriod);
  add('Overview', 'Cancelled transactions', data.overview.cancelled_transactions, filteredPeriod);

  add('Users', 'Total users', data.users.total);
  add('Users', 'Buyers', data.users.buyers);
  add('Users', 'Sellers', data.users.sellers);
  add('Users', 'Administrators', data.users.admins);
  data.users.registration_trend.forEach((item) => {
    add('Users', `Registrations (${item.month})`, item.count, filteredPeriod);
  });
  data.users.seller_distribution.forEach((item) => {
    add('Users', `Seller distribution: ${item.label}`, item.count);
  });

  add('Listings', 'Total listings', data.listings.total, filteredPeriod);
  add('Listings', 'Active listings', data.listings.active);
  add('Listings', 'Sold listings', data.listings.sold);
  add('Listings', 'Pending listings', data.listings.pending);
  add('Listings', 'Draft listings', data.listings.draft);
  add('Listings', 'Inactive listings', data.listings.inactive);
  data.listings.by_type.forEach((item) => {
    add('Listings', `By livestock type: ${item.type}`, item.count, filteredPeriod);
  });
  data.listings.by_status.forEach((item) => {
    add('Listings', `By status: ${item.status}`, item.count);
  });
  add('Listings', 'Average asking price', data.listings.price_stats.avg_price, filteredPeriod);
  add('Listings', 'Minimum asking price', data.listings.price_stats.min_price, filteredPeriod);
  add('Listings', 'Maximum asking price', data.listings.price_stats.max_price, filteredPeriod);
  add('Listings', 'Total asking-price value', data.listings.price_stats.total_value, filteredPeriod);

  add('Transactions', 'Total transactions', data.transactions.total, filteredPeriod);
  add('Transactions', 'Pending transactions', data.transactions.pending, filteredPeriod);
  add('Transactions', 'Completed transactions', data.transactions.completed, filteredPeriod);
  add('Transactions', 'Cancelled transactions', data.transactions.cancelled, filteredPeriod);
  add(
    'Transactions',
    'Recorded arrangement value (completed transactions)',
    data.transactions.total_revenue,
    filteredPeriod,
  );
  add('Transactions', 'Average completed transaction amount', data.transactions.avg_amount, filteredPeriod);
  data.transactions.trend.forEach((item) => {
    add('Transactions', `Transactions (${item.month})`, item.count, filteredPeriod);
    add(
      'Transactions',
      `Recorded arrangement value (${item.month}, completed transactions)`,
      item.revenue,
      filteredPeriod,
    );
  });
  data.transactions.by_status.forEach((item) => {
    add('Transactions', `By status: ${item.status}`, item.count, filteredPeriod);
  });
  data.transactions.by_livestock.forEach((item) => {
    add('Transactions', `By livestock type: ${item.livestock_type} (count)`, item.count, filteredPeriod);
    add(
      'Transactions',
      `By livestock type: ${item.livestock_type} (recorded transaction amount)`,
      item.total_amount,
      filteredPeriod,
    );
  });

  add('Seller verifications', 'Total submission records', data.seller_verifications.total, filteredPeriod);
  add('Seller verifications', 'Submitted', data.seller_verifications.submitted, filteredPeriod);
  add('Seller verifications', 'Pending review', data.seller_verifications.pending_review, filteredPeriod);
  add('Seller verifications', 'Approved', data.seller_verifications.approved, filteredPeriod);
  add('Seller verifications', 'Rejected', data.seller_verifications.rejected, filteredPeriod);
  data.seller_verifications.submission_trend.forEach((item) => {
    add('Seller verifications', `Submissions (${item.month})`, item.count, filteredPeriod);
  });
  data.seller_verifications.status_distribution.forEach((item) => {
    add('Seller verifications', `By status: ${item.status}`, item.count, filteredPeriod);
  });

  add('Activities', 'Total activities', data.activities.total, filteredPeriod);
  data.activities.by_action.forEach((item) => {
    add('Activities', `By action: ${item.action}`, item.count, filteredPeriod);
  });
  data.activities.trend.forEach((item) => {
    add('Activities', `Activities (${item.month})`, item.count, filteredPeriod);
  });
  data.activities.by_user.forEach((item) => {
    const actor = item.user_id === null ? 'System' : `${item.user_name} (ID ${item.user_id})`;
    add('Activities', `By user: ${actor}`, item.count, filteredPeriod);
  });

  return buildCsvContent(rows);
}

function pad(value: number): string {
  return String(value).padStart(2, '0');
}

export function buildReportsFilename(params: ReportParams = {}, now = new Date()): string {
  const range = params.date_from && params.date_to
    ? `${params.date_from}-to-${params.date_to}`
    : params.date_from
      ? `from-${params.date_from}`
      : params.date_to
        ? `through-${params.date_to}`
        : 'all-time';
  const timestamp = `${now.getFullYear()}${pad(now.getMonth() + 1)}${pad(now.getDate())}-${pad(now.getHours())}${pad(now.getMinutes())}${pad(now.getSeconds())}`;

  return `agrobenta-reports-${range}-${timestamp}.csv`;
}
