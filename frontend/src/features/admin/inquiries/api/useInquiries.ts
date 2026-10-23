import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import api from '../../../../lib/api';

export type InquiryStatusValue = 'open' | 'responded' | 'closed';

export type InquiryTransactionMethodValue = 'direct_deal' | 'arrange_delivery';

export type InquiryContactMethodValue = 'in_app_message';

export interface InquiryParty {
  id: number;
  name: string;
  email: string;
}

export interface InquiryListing {
  id: number;
  livestock_type: string;
  breed: string;
}

export interface Inquiry {
  id: number;
  buyer: InquiryParty;
  seller: InquiryParty;
  listing: InquiryListing | null;
  subject: string | null;
  message: string;
  purchase_interest: boolean | null;
  transaction_method: InquiryTransactionMethodValue | null;
  delivery_method: string | null;
  /** A decimal string from the API, never re-parsed. */
  delivery_fee: string | null;
  contact_method: InquiryContactMethodValue | null;
  preferred_schedule: string | null;
  status: InquiryStatusValue;
  created_at: string;
  updated_at: string;
}

export interface InquiriesPagination {
  current_page: number;
  last_page: number;
  per_page: number;
  total: number;
}

export interface InquiriesData {
  inquiries: Inquiry[];
  pagination: InquiriesPagination;
}

interface InquiriesResponse {
  success: boolean;
  data: InquiriesData;
}

export interface InquiriesParams {
  search?: string;
  status?: string;
  page?: number;
  per_page?: number;
}

export async function fetchInquiries(params: InquiriesParams): Promise<InquiriesData> {
  const query = new URLSearchParams();
  if (params.search) query.set('search', params.search);
  if (params.status) query.set('status', params.status);
  if (params.page) query.set('page', String(params.page));
  if (params.per_page) query.set('per_page', String(params.per_page));

  const qs = query.toString();
  const url = `/admin/inquiries${qs ? `?${qs}` : ''}`;

  const response = await api.get<InquiriesResponse>(url);
  return response.data.data;
}

export function useInquiries(params: InquiriesParams) {
  return useQuery({
    queryKey: ['admin', 'inquiries', params],
    queryFn: () => fetchInquiries(params),
    staleTime: 30_000,
    refetchOnWindowFocus: false,
    retry: 1,
  });
}

export async function fetchInquiry(id: number): Promise<Inquiry> {
  const response = await api.get<{ success: boolean; data: Inquiry }>(`/admin/inquiries/${id}`);
  return response.data.data;
}

/**
 * A single inquiry by id, so the detail dialog can open a row that is not on the
 * page the list happens to be showing.
 */
export function useInquiry(id: number | null) {
  return useQuery({
    queryKey: ['admin', 'inquiries', 'detail', id],
    queryFn: () => fetchInquiry(id as number),
    enabled: id !== null,
    staleTime: 30_000,
    refetchOnWindowFocus: false,
    retry: 0,
  });
}

export async function updateInquiryStatus(id: number, status: string): Promise<Inquiry> {
  const response = await api.patch<{ success: boolean; data: Inquiry }>(
    `/admin/inquiries/${id}/status`,
    { status },
  );
  return response.data.data;
}

/**
 * Change an inquiry's workflow status. Invalidates both the list (any filter)
 * and the open detail so the badge and the dialog cannot disagree.
 */
export function useUpdateInquiryStatus() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: ({ id, status }: { id: number; status: string }) =>
      updateInquiryStatus(id, status),
    onSuccess: () => {
      void queryClient.invalidateQueries({ queryKey: ['admin', 'inquiries'] });
    },
  });
}

export async function deleteInquiry(id: number): Promise<void> {
  await api.delete(`/admin/inquiries/${id}`);
}

export function useDeleteInquiry() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: (id: number) => deleteInquiry(id),
    onSuccess: () => {
      void queryClient.invalidateQueries({ queryKey: ['admin', 'inquiries'] });
    },
  });
}
