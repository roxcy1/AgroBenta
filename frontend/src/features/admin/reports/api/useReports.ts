import { useQuery } from '@tanstack/react-query';
import api from '../../../../lib/api';

export interface ReportOverview {
  total_users: number;
  buyer_accounts: number;
  approved_sellers: number;
  total_listings: number;
  active_listings: number;
  sold_listings: number;
  pending_listings: number;
  total_transactions: number;
  pending_transactions: number;
  completed_transactions: number;
  cancelled_transactions: number;
}

export interface ReportUserTrend {
  month: string;
  count: number;
}

export interface ReportSellerDist {
  label: string;
  count: number;
}

export interface ReportUsers {
  total: number;
  buyers: number;
  sellers: number;
  admins: number;
  registration_trend: ReportUserTrend[];
  seller_distribution: ReportSellerDist[];
}

export interface ReportPriceStats {
  avg_price: number;
  min_price: number;
  max_price: number;
  total_value: number;
}

export interface ReportListings {
  total: number;
  active: number;
  sold: number;
  pending: number;
  draft: number;
  inactive: number;
  by_type: Array<{ type: string; count: number }>;
  by_status: Array<{ status: string; count: number }>;
  price_stats: ReportPriceStats;
}

export interface ReportTransactionTrend {
  month: string;
  count: number;
  revenue: number;
}

export interface ReportTransactions {
  total: number;
  pending: number;
  completed: number;
  cancelled: number;
  total_revenue: number;
  avg_amount: number;
  trend: ReportTransactionTrend[];
  by_status: Array<{ status: string; count: number }>;
  by_livestock: Array<{ livestock_type: string; count: number; total_amount: number }>;
}

export interface ReportSellerVerifications {
  total: number;
  submitted: number;
  pending_review: number;
  approved: number;
  rejected: number;
  submission_trend: Array<{ month: string; count: number }>;
  status_distribution: Array<{ status: string; count: number }>;
}

export interface ReportActivities {
  total: number;
  by_action: Array<{ action: string; count: number }>;
  trend: Array<{ month: string; count: number }>;
  by_user: Array<{ user_id: number | null; user_name: string; count: number }>;
}

export interface ReportData {
  overview: ReportOverview;
  users: ReportUsers;
  listings: ReportListings;
  transactions: ReportTransactions;
  seller_verifications: ReportSellerVerifications;
  activities: ReportActivities;
}

interface ReportResponse {
  success: boolean;
  data: ReportData;
}

export interface ReportParams {
  date_from?: string;
  date_to?: string;
}

async function fetchReports(params: ReportParams): Promise<ReportData> {
  const query = new URLSearchParams();
  if (params.date_from) query.set('date_from', params.date_from);
  if (params.date_to) query.set('date_to', params.date_to);

  const qs = query.toString();
  const url = `/admin/reports${qs ? `?${qs}` : ''}`;

  const response = await api.get<ReportResponse>(url);
  return response.data.data;
}

export function useReports(params: ReportParams = {}) {
  return useQuery({
    queryKey: ['admin', 'reports', params],
    queryFn: () => fetchReports(params),
    staleTime: 30_000,
    refetchOnWindowFocus: false,
    retry: 1,
  });
}
