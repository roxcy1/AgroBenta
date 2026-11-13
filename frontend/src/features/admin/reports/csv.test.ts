import { describe, expect, it } from 'vitest';
import type { ReportData } from './api/useReports';
import { buildReportsCsv, buildReportsFilename } from './csv';

function makeReportData(): ReportData {
  return {
    overview: {
      total_users: 10,
      buyer_accounts: 6,
      approved_sellers: 4,
      total_listings: 8,
      active_listings: 5,
      sold_listings: 1,
      pending_listings: 2,
      total_transactions: 3,
      pending_transactions: 1,
      completed_transactions: 2,
      cancelled_transactions: 0,
    },
    users: {
      total: 10,
      buyers: 6,
      sellers: 4,
      admins: 1,
      registration_trend: [{ month: '2026-01', count: 3 }],
      seller_distribution: [
        { label: 'Buyers', count: 6 },
        { label: 'Sellers', count: 4 },
      ],
    },
    listings: {
      total: 8,
      active: 5,
      sold: 1,
      pending: 2,
      draft: 0,
      inactive: 0,
      by_type: [{ type: 'Cattle', count: 5 }],
      by_status: [{ status: 'active', count: 5 }],
      price_stats: { avg_price: 12500, min_price: 8000, max_price: 20000, total_value: 62500 },
    },
    transactions: {
      total: 3,
      pending: 1,
      completed: 2,
      cancelled: 0,
      total_revenue: 50000,
      avg_amount: 25000,
      trend: [{ month: '2026-01', count: 2, revenue: 50000 }],
      by_status: [{ status: 'completed', count: 2 }],
      by_livestock: [{ livestock_type: 'Cattle', count: 2, total_amount: 50000 }],
    },
    seller_verifications: {
      total: 4,
      submitted: 1,
      pending_review: 1,
      approved: 1,
      rejected: 1,
      submission_trend: [{ month: '2026-01', count: 4 }],
      status_distribution: [{ status: 'approved', count: 1 }],
    },
    activities: {
      total: 2,
      by_action: [{ action: 'settings_updated', count: 1 }],
      trend: [{ month: '2026-01', count: 2 }],
      by_user: [{ user_id: 7, user_name: 'Admin User', count: 2 }],
    },
  };
}

describe('buildReportsCsv', () => {
  it('exports every report section and the currently applied date range', () => {
    const csv = buildReportsCsv(makeReportData(), {
      date_from: '2026-01-01',
      date_to: '2026-01-31',
    });

    expect(csv.split('\r\n')[0]).toBe('Section,Metric,Period,Value');
    expect(csv).toContain('Report,Applied date range,2026-01-01 through 2026-01-31,');
    expect(csv).toContain('Overview,Total users,All-time,10');
    expect(csv).toContain('Users,Registrations (2026-01),2026-01-01 through 2026-01-31,3');
    expect(csv).toContain('Listings,By livestock type: Cattle,2026-01-01 through 2026-01-31,5');
    expect(csv).toContain('Transactions,Recorded arrangement value (completed transactions),2026-01-01 through 2026-01-31,50000');
    expect(csv).toContain('Seller verifications,Total submission records,2026-01-01 through 2026-01-31,4');
    expect(csv).toContain('Activities,By user: Admin User (ID 7),2026-01-01 through 2026-01-31,2');
    expect(csv).toContain('User totals and listing status counts are all-time.');
  });

  it('exports every returned breakdown entry and escapes CSV text safely', () => {
    const data = makeReportData();
    data.activities.by_action = [
      { action: 'custom, "review" action', count: 2 },
      ...Array.from({ length: 9 }, (_, index) => ({ action: `action_${index}`, count: index })),
    ];

    const csv = buildReportsCsv(data);

    expect(csv).toContain('Activities,"By action: custom, ""review"" action",All-time,2');
    expect(csv).toContain('Activities,By action: action_8,All-time,8');
  });

  it('keeps a valid header and metadata when grouped sections are empty', () => {
    const data = makeReportData();
    data.users.registration_trend = [];
    data.users.seller_distribution = [];
    data.listings.by_type = [];
    data.listings.by_status = [];
    data.transactions.trend = [];
    data.transactions.by_status = [];
    data.transactions.by_livestock = [];
    data.seller_verifications.submission_trend = [];
    data.seller_verifications.status_distribution = [];
    data.activities.by_action = [];
    data.activities.trend = [];
    data.activities.by_user = [];

    const csv = buildReportsCsv(data);

    expect(csv.split('\r\n')[0]).toBe('Section,Metric,Period,Value');
    expect(csv).toContain('Report,Applied date range,All-time,');
    expect(csv).toContain('Activities,Total activities,All-time,2');
  });
});

describe('buildReportsFilename', () => {
  it('includes the selected range and a sortable timestamp', () => {
    const filename = buildReportsFilename(
      { date_from: '2026-01-01', date_to: '2026-01-31' },
      new Date(2026, 0, 12, 6, 5, 9),
    );

    expect(filename).toBe('agrobenta-reports-2026-01-01-to-2026-01-31-20260112-060509.csv');
  });

  it('uses an all-time label when no range is applied', () => {
    expect(buildReportsFilename({}, new Date(2026, 0, 12, 6, 5, 9)))
      .toBe('agrobenta-reports-all-time-20260112-060509.csv');
  });
});
