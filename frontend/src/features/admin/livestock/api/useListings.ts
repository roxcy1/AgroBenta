import { useQuery } from '@tanstack/react-query';
import api from '../../../../lib/api';

export interface ListingSeller {
  id: number;
  name: string;
  email: string;
}

export interface Listing {
  id: number;
  seller: ListingSeller;
  livestock_type: string;
  breed: string;
  age_value: number | null;
  age_unit: string | null;
  gender: string | null;
  weight_value: number | null;
  weight_unit: string | null;
  quantity: number;
  asking_price: string;
  location: string;
  health_status: string | null;
  vaccination: string | null;
  short_description: string;
  additional_notes: string | null;
  status: 'draft' | 'pending' | 'active' | 'sold' | 'inactive';
  created_at: string;
  updated_at: string;
}

export interface ListingsPagination {
  current_page: number;
  last_page: number;
  per_page: number;
  total: number;
}

export interface ListingsData {
  listings: Listing[];
  pagination: ListingsPagination;
}

interface ListingsResponse {
  success: boolean;
  data: ListingsData;
}

export interface ListingsParams {
  search?: string;
  livestock_type?: string;
  status?: string;
  page?: number;
  per_page?: number;
}

async function fetchListings(params: ListingsParams): Promise<ListingsData> {
  const query = new URLSearchParams();
  if (params.search) query.set('search', params.search);
  if (params.livestock_type) query.set('livestock_type', params.livestock_type);
  if (params.status) query.set('status', params.status);
  if (params.page) query.set('page', String(params.page));
  if (params.per_page) query.set('per_page', String(params.per_page));

  const qs = query.toString();
  const url = `/admin/listings${qs ? `?${qs}` : ''}`;

  const response = await api.get<ListingsResponse>(url);
  return response.data.data;
}

export function useListings(params: ListingsParams) {
  return useQuery({
    queryKey: ['admin', 'listings', params],
    queryFn: () => fetchListings(params),
    staleTime: 30_000,
    refetchOnWindowFocus: false,
    retry: 1,
  });
}
