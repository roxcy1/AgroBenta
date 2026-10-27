import { useQuery } from '@tanstack/react-query';
import api from '../../../../lib/api';
import type { UserVerificationInfo } from './useUsers';

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
  id_document_ref: string | null;
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

export interface VerificationsParams {
  search?: string;
  status?: string;
  page?: number;
  per_page?: number;
}

export const USER_VERIFICATIONS_QUERY_KEY = ['admin', 'seller-verifications'] as const;

async function fetchVerifications(params: VerificationsParams = {}): Promise<VerificationsData> {
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

export function useSellerVerificationsList(params: VerificationsParams = {}) {
  return useQuery({
    queryKey: [...USER_VERIFICATIONS_QUERY_KEY, params],
    queryFn: () => fetchVerifications(params),
    staleTime: 30_000,
    refetchOnWindowFocus: false,
    retry: 1,
  });
}

export function buildUserVerificationMap(
  verifications: SellerVerification[],
): Map<number, UserVerificationInfo> {
  const map = new Map<number, UserVerificationInfo>();
  for (const v of verifications) {
    const sellerId = v.seller?.id;
    if (sellerId === undefined || sellerId === null) continue;
    // latest per applicant already provided by list; keep first/overwrite consistently
    if (!map.has(sellerId)) {
      map.set(sellerId, {
        verificationId: v.id,
        status: v.status,
      });
    } else {
      // ensure we keep latest if somehow not; repo dedupes, just in case
      const existing = map.get(sellerId);
      if (existing && existing.verificationId === null) {
        map.set(sellerId, { verificationId: v.id, status: v.status });
      }
    }
  }
  return map;
}

export function useUserVerificationsMap(params: VerificationsParams = {}) {
  const query = useSellerVerificationsList(params);
  const map = buildUserVerificationMap(query.data?.verifications ?? []);
  return {
    ...query,
    map,
    verifications: query.data?.verifications ?? [],
    pagination: query.data?.pagination,
  };
}
