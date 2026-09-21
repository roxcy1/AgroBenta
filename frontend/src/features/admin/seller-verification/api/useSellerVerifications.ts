import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import api from '../../../../lib/api';

export interface VerificationSeller {
  id: number;
  name: string;
  email: string;
}

export interface VerificationReviewer {
  id: number;
  name: string;
}

export interface SellerVerification {
  id: number;
  seller: VerificationSeller;
  business_name: string;
  business_location: string | null;
  business_description: string | null;
  status: 'submitted' | 'pending_review' | 'approved' | 'rejected';
  admin_note: string | null;
  submitted_at: string | null;
  reviewed_at: string | null;
  reviewer: VerificationReviewer | null;
  created_at: string;
  updated_at: string;
}

export interface VerificationsPagination {
  current_page: number;
  last_page: number;
  per_page: number;
  total: number;
}

export interface VerificationsData {
  verifications: SellerVerification[];
  pagination: VerificationsPagination;
}

interface VerificationsResponse {
  success: boolean;
  data: VerificationsData;
}

interface ReviewResponse {
  success: boolean;
  message: string;
  data: SellerVerification;
}

export interface VerificationsParams {
  search?: string;
  status?: string;
  page?: number;
  per_page?: number;
}

async function fetchVerifications(params: VerificationsParams): Promise<VerificationsData> {
  const query = new URLSearchParams();
  if (params.search) query.set('search', params.search);
  if (params.status) query.set('status', params.status);
  if (params.page) query.set('page', String(params.page));
  if (params.per_page) query.set('per_page', String(params.per_page));

  const qs = query.toString();
  const url = `/admin/seller-verifications${qs ? `?${qs}` : ''}`;

  const response = await api.get<VerificationsResponse>(url);
  return response.data.data;
}

async function approveVerification(id: number, adminNote?: string): Promise<ReviewResponse> {
  const response = await api.post<ReviewResponse>(
    `/admin/seller-verifications/${id}/approve`,
    adminNote ? { admin_note: adminNote } : {},
  );
  return response.data;
}

async function rejectVerification(id: number, adminNote?: string): Promise<ReviewResponse> {
  const response = await api.post<ReviewResponse>(
    `/admin/seller-verifications/${id}/reject`,
    adminNote ? { admin_note: adminNote } : {},
  );
  return response.data;
}

export function useSellerVerifications(params: VerificationsParams) {
  return useQuery({
    queryKey: ['admin', 'seller-verifications', params],
    queryFn: () => fetchVerifications(params),
    staleTime: 30_000,
    refetchOnWindowFocus: false,
    retry: 1,
  });
}

export function useApproveVerification() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: ({ id, adminNote }: { id: number; adminNote?: string }) =>
      approveVerification(id, adminNote),
    onSuccess: () => {
      void queryClient.invalidateQueries({ queryKey: ['admin', 'seller-verifications'] });
    },
  });
}

export function useRejectVerification() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: ({ id, adminNote }: { id: number; adminNote?: string }) =>
      rejectVerification(id, adminNote),
    onSuccess: () => {
      void queryClient.invalidateQueries({ queryKey: ['admin', 'seller-verifications'] });
    },
  });
}
