import { useQuery } from '@tanstack/react-query';
import api from '../../../lib/api';
import type { ListingStatus } from '../livestock/components/listingModeration';

export interface DashboardSummary {
  total_users: number;
  buyer_accounts: number;
  approved_sellers: number;
  pending_verifications: number;
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

export interface DashboardRecentListing {
  id: number;
  livestock_type: string;
  breed: string;
  asking_price: string;
  status: ListingStatus;
  seller: DashboardActivityUser | null;
  created_at: string;
}

export interface DashboardTransactionListing {
  id: number;
  livestock_type: string;
  breed: string;
}

export interface DashboardRecentTransaction {
  id: number;
  buyer: DashboardActivityUser | null;
  seller: DashboardActivityUser | null;
  listing: DashboardTransactionListing | null;
  quantity: number;
  total_amount: string;
  status: 'pending' | 'completed' | 'cancelled';
  created_at: string;
}

export interface DashboardData {
  summary: DashboardSummary;
  listings: DashboardListings;
  transactions: DashboardTransactions;
  transaction_trend: TransactionTrendItem[];
  livestock_distribution: LivestockDistributionItem[];
  recent_activities: DashboardActivity[];
  recent_listings: DashboardRecentListing[];
  recent_transactions: DashboardRecentTransaction[];
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
