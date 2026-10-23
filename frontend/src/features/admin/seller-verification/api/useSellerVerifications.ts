import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import api from '../../../../lib/api';
import {
  verificationPollingInterval,
  type VerificationStatus,
} from '../components/verificationModeration';

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
  has_id_document: boolean;
  has_selfie: boolean;
  status: VerificationStatus;
  admin_note: string | null;
  submitted_at: string | null;
  reviewed_at: string | null;
  reviewer: VerificationReviewer | null;
  created_at: string;
  updated_at: string;
}

/**
 * The two evidence documents an application can carry.
 *
 * These are the `type` values the streaming endpoint accepts, and the same
 * values the server reports through `has_id_document` / `has_selfie`.
 */
export type VerificationDocumentType = 'id_document' | 'selfie';

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

/**
 * `GET /admin/seller-verifications/{id}` returns the record and, under a
 * top-level `history` key, the applicant's prior submissions newest-first.
 */
interface VerificationDetailResponse {
  success: boolean;
  data: SellerVerification;
  history: SellerVerification[];
}

export interface VerificationDetail {
  verification: SellerVerification;
  history: SellerVerification[];
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

async function fetchVerificationDetail(id: number): Promise<VerificationDetail> {
  const response = await api.get<VerificationDetailResponse>(`/admin/seller-verifications/${id}`);

  return {
    verification: response.data.data,
    history: response.data.history ?? [],
  };
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

/**
 * `GET /admin/seller-verifications/{id}/documents/{type}` returns the file
 * bytes themselves — not a JSON envelope — from the private disk.
 *
 * The response is deliberately not parsed as JSON: `responseType: 'blob'` keeps
 * axios from running `JSON.parse` on an image. The admin token is attached by
 * the shared request interceptor, so the fetch is authenticated the same way as
 * every other admin call and the bytes never need a public URL.
 */
export async function fetchVerificationDocument(
  id: number,
  type: VerificationDocumentType,
): Promise<Blob> {
  const response = await api.get<Blob>(
    `/admin/seller-verifications/${id}/documents/${type}`,
    { responseType: 'blob' },
  );
  return response.data;
}

export function useSellerVerifications(params: VerificationsParams) {
  return useQuery({
    queryKey: ['admin', 'seller-verifications', params],
    queryFn: () => fetchVerifications(params),
    staleTime: 30_000,
    refetchOnWindowFocus: false,
    refetchInterval: verificationPollingInterval,
    retry: 1,
  });
}

/**
 * One applicant's verification record together with their prior submissions.
 *
 * The list endpoint deduplicates to the latest record per applicant, so the
 * older rows are never visible in the table — the drawer is the only place the
 * history can be read, and it is read-only there.
 */
export function useSellerVerification(id: number) {
  return useQuery({
    queryKey: ['admin', 'seller-verifications', 'detail', id],
    queryFn: () => fetchVerificationDetail(id),
    staleTime: 30_000,
    refetchOnWindowFocus: false,
    refetchInterval: verificationPollingInterval,
    retry: 1,
  });
}

export interface SellerVerificationCounts {
  submitted: number;
  pending_review: number;
  approved: number;
  rejected: number;
}

/**
 * Aggregate counts for the four verification tabs.
 *
 * There is no counting endpoint, and one is not needed: `GET
 * /admin/seller-verifications` already reports `pagination.total` for the query
 * it ran — the server's `count(*)`, not the size of the page. Asking it once per
 * status with `per_page=1` therefore yields exact totals without a new backend
 * surface. Because the list is deduplicated to the latest record per applicant,
 * each record is counted under exactly one status.
 */
export async function fetchVerificationCounts(): Promise<SellerVerificationCounts> {
  const [submitted, pendingReview, approved, rejected] = await Promise.all([
    fetchVerifications({ status: 'submitted', per_page: 1 }),
    fetchVerifications({ status: 'pending_review', per_page: 1 }),
    fetchVerifications({ status: 'approved', per_page: 1 }),
    fetchVerifications({ status: 'rejected', per_page: 1 }),
  ]);

  return {
    submitted: submitted.pagination.total,
    pending_review: pendingReview.pagination.total,
    approved: approved.pagination.total,
    rejected: rejected.pagination.total,
  };
}

/**
 * The query key shares the `['admin', 'seller-verifications']` prefix, so the
 * approve/reject mutations — which invalidate that prefix — refresh the counts
 * along with the list and any open detail view.
 */
export function useSellerVerificationCounts() {
  return useQuery({
    queryKey: ['admin', 'seller-verifications', 'counts'],
    queryFn: fetchVerificationCounts,
    staleTime: 30_000,
    refetchOnWindowFocus: false,
    refetchInterval: verificationPollingInterval,
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
