import { useQuery } from '@tanstack/react-query';
import api from '../../../lib/api';

export interface DashboardSummary {
  total_users: number;
  buyer_accounts: number;
  approved_sellers: number;
  total_listings: number;
  active_listings: number;
  total_transactions: number;
}

export interface DashboardListings {
  total: number;
  active: number;
  sold: number;
  pending: number;
  draft: number;
  inactive: number;
}

export interface DashboardTransactions {
  total: number;
  pending: number;
  completed: number;
  cancelled: number;
}

export interface TransactionTrendItem {
  month: string;
  count: number;
  revenue: number;
}

export interface LivestockDistributionItem {
  type: string;
  count: number;
}

export interface DashboardActivityUser {
  id: number;
  name: string;
}

export interface DashboardActivity {
  id: number;
  action: string;
  description: string;
  created_at: string;
  user: DashboardActivityUser | null;
}

export interface DashboardData {
  summary: DashboardSummary;
  listings: DashboardListings;
  transactions: DashboardTransactions;
  transaction_trend: TransactionTrendItem[];
  livestock_distribution: LivestockDistributionItem[];
  recent_activities: DashboardActivity[];
}

interface DashboardResponse {
  success: boolean;
  data: DashboardData;
}

async function fetchDashboard(): Promise<DashboardData> {
  const response = await api.get<DashboardResponse>('/admin/dashboard');
  return response.data.data;
}

export function useDashboard() {
  return useQuery({
    queryKey: ['admin', 'dashboard'],
    queryFn: fetchDashboard,
    staleTime: 30_000,
    refetchOnWindowFocus: false,
    retry: 1,
  });
}
