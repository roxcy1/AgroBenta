import { useQuery } from '@tanstack/react-query';
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

async function fetchUsers(params: UsersParams): Promise<UsersData> {
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
    staleTime: 30_000,
    refetchOnWindowFocus: false,
    retry: 1,
  });
}
