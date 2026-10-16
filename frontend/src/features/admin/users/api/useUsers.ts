import { keepPreviousData, useQuery } from '@tanstack/react-query';
import api from '../../../../lib/api';

export interface AdminUser {
  id: number;
  name: string;
  email: string;
  role: 'user' | 'admin';
  seller_capability: 'buyer' | 'seller';
  email_verified_at: string | null;
  created_at: string;
  updated_at: string;
}

export interface UserVerificationInfo {
  verificationId: number | null;
  status: 'submitted' | 'pending_review' | 'approved' | 'rejected' | null;
}

export interface UsersPagination {
  current_page: number;
  last_page: number;
  per_page: number;
  total: number;
}

export interface UsersData {
  users: AdminUser[];
  pagination: UsersPagination;
}

interface UsersResponse {
  success: boolean;
  data: UsersData;
}

export interface UsersParams {
  search?: string;
  role?: string;
  seller_capability?: string;
  page?: number;
  per_page?: number;
}

export async function fetchUsers(params: UsersParams): Promise<UsersData> {
  const query = new URLSearchParams();
  if (params.search) query.set('search', params.search);
  if (params.role) query.set('role', params.role);
  if (params.seller_capability) query.set('seller_capability', params.seller_capability);
  if (params.page) query.set('page', String(params.page));
  if (params.per_page) query.set('per_page', String(params.per_page));

  const qs = query.toString();
  const url = `/admin/users${qs ? `?${qs}` : ''}`;

  const response = await api.get<UsersResponse>(url);
  return response.data.data;
}

export function useUsers(params: UsersParams) {
  return useQuery({
    queryKey: ['admin', 'users', params],
    queryFn: () => fetchUsers(params),
    placeholderData: keepPreviousData,
    staleTime: 30_000,
    refetchOnWindowFocus: false,
    retry: 1,
  });
}

export async function fetchAdminUser(id: number): Promise<AdminUser> {
  const response = await api.get<{ success: boolean; data: AdminUser }>(`/admin/users/${id}`);
  return response.data.data;
}

/**
 * A single user by id.
 *
 * The users surface has no detail screen, so a `?user=` deep link resolves the
 * record here and focuses the list on that account rather than linking to a
 * dead page.
 */
export function useAdminUser(id: number | null) {
  return useQuery({
    queryKey: ['admin', 'users', 'detail', id],
    queryFn: () => fetchAdminUser(id as number),
    enabled: id !== null,
    staleTime: 30_000,
    refetchOnWindowFocus: false,
    retry: 0,
  });
}

export interface UserStatusCounts {
  total: number;
  buyers: number;
  sellers: number;
  admins: number;
}

/**
 * Aggregate user counts for the summary cards.
 *
 * There is no counting endpoint, and one is not needed: `GET /admin/users`
 * already reports `pagination.total` for the query it ran, which is the server's
 * `count(*)`, not the size of the page it returned. Asking it once per segment
 * with `per_page=1` therefore yields exact totals without a new backend surface.
 *
 * All four requests share one query key, so the cards have a single loading
 * state and any later `['admin', 'users']` invalidation refreshes them too.
 */
export function useUserCounts() {
  return useQuery({
    queryKey: ['admin', 'users', 'counts'],
    queryFn: async (): Promise<UserStatusCounts> => {
      const [all, buyers, sellers, admins] = await Promise.all([
        fetchUsers({ per_page: 1 }),
        fetchUsers({ seller_capability: 'buyer', per_page: 1 }),
        fetchUsers({ seller_capability: 'seller', per_page: 1 }),
        fetchUsers({ role: 'admin', per_page: 1 }),
      ]);

      return {
        total: all.pagination.total,
        buyers: buyers.pagination.total,
        sellers: sellers.pagination.total,
        admins: admins.pagination.total,
      };
    },
    staleTime: 30_000,
  });
}
