import { useQuery } from '@tanstack/react-query';
import api from '../../../../lib/api';

export interface TransactionBuyer {
  id: number;
  name: string;
  email: string;
}

export interface TransactionSeller {
  id: number;
  name: string;
  email: string;
}

export interface TransactionListing {
  id: number;
  livestock_type: string;
  breed: string;
}

export interface Transaction {
  id: number;
  buyer: TransactionBuyer;
  seller: TransactionSeller;
  listing: TransactionListing;
  quantity: number;
  total_amount: string;
  status: 'pending' | 'completed' | 'cancelled';
  created_at: string;
  updated_at: string;
}

export interface TransactionsPagination {
  current_page: number;
  last_page: number;
  per_page: number;
  total: number;
}

export interface TransactionsData {
  transactions: Transaction[];
  pagination: TransactionsPagination;
}

interface TransactionsResponse {
  success: boolean;
  data: TransactionsData;
}

export interface TransactionsParams {
  search?: string;
  status?: string;
  date_from?: string;
  date_to?: string;
  page?: number;
  per_page?: number;
}

async function fetchTransactions(params: TransactionsParams): Promise<TransactionsData> {
  const query = new URLSearchParams();
  if (params.search) query.set('search', params.search);
  if (params.status) query.set('status', params.status);
  if (params.date_from) query.set('date_from', params.date_from);
  if (params.date_to) query.set('date_to', params.date_to);
  if (params.page) query.set('page', String(params.page));
  if (params.per_page) query.set('per_page', String(params.per_page));

  const qs = query.toString();
  const url = `/admin/transactions${qs ? `?${qs}` : ''}`;

  const response = await api.get<TransactionsResponse>(url);
  return response.data.data;
}

/**
 * Fetches every transaction matching the given filters, walking all pages.
 *
 * The backend caps `per_page` at 100, so each page is requested at that size and
 * iteration continues until the reported `last_page` is reached. Results are
 * returned in the same order the API serves them.
 */
export async function fetchAllTransactions(
  params: Omit<TransactionsParams, 'page' | 'per_page'>,
): Promise<Transaction[]> {
  const firstPage = await fetchTransactions({ ...params, page: 1, per_page: 100 });
  const all: Transaction[] = [...firstPage.transactions];
  const lastPage = firstPage.pagination.last_page;

  for (let page = 2; page <= lastPage; page += 1) {
    const nextPage = await fetchTransactions({ ...params, page, per_page: 100 });
    all.push(...nextPage.transactions);
  }

  return all;
}

export function useTransactions(params: TransactionsParams) {
  return useQuery({
    queryKey: ['admin', 'transactions', params],
    queryFn: () => fetchTransactions(params),
    staleTime: 30_000,
    refetchOnWindowFocus: false,
    retry: 1,
  });
}

export interface TransactionStatusCounts {
  total: number;
  pending: number;
  completed: number;
  cancelled: number;
}

/**
 * Aggregate transaction counts for the status cards.
 *
 * The list endpoint already reports `pagination.total` for the query it ran,
 * which is the server's `count(*)` rather than the size of the returned page.
 * Requesting one row per status therefore yields exact totals without adding a
 * counting endpoint. The four requests share a single query key so the cards
 * have one loading state.
 */
export function useTransactionCounts() {
  return useQuery({
    queryKey: ['admin', 'transactions', 'counts'],
    queryFn: async (): Promise<TransactionStatusCounts> => {
      const [all, pending, completed, cancelled] = await Promise.all([
        fetchTransactions({ per_page: 1 }),
        fetchTransactions({ status: 'pending', per_page: 1 }),
        fetchTransactions({ status: 'completed', per_page: 1 }),
        fetchTransactions({ status: 'cancelled', per_page: 1 }),
      ]);

      return {
        total: all.pagination.total,
        pending: pending.pagination.total,
        completed: completed.pagination.total,
        cancelled: cancelled.pagination.total,
      };
    },
    staleTime: 30_000,
    refetchOnWindowFocus: false,
    retry: 1,
  });
}
