import { keepPreviousData, useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import api from '../../../../lib/api';

export type UserReportStatus = 'pending' | 'dismissed' | 'actioned';

export interface UserReportPerson {
  id: number;
  name: string;
  status?: 'active' | 'deactivated';
  pending_transactions_count?: number;
}

export interface AdminUserReport {
  id: number;
  reason: string;
  reason_label: string;
  description: string;
  status: UserReportStatus;
  status_label: string;
  reporter: UserReportPerson | null;
  reported_user: UserReportPerson | null;
  has_evidence: boolean;
  reviewer: { id: number; name: string } | null;
  reviewed_at: string | null;
  admin_note: string | null;
  created_at: string;
}

export interface UserReportsPagination {
  current_page: number;
  last_page: number;
  per_page: number;
  total: number;
}

export interface UserReportsData {
  reports: AdminUserReport[];
  pagination: UserReportsPagination;
}

interface UserReportsResponse {
  success: boolean;
  data: UserReportsData;
}

interface UserReportResponse {
  success: boolean;
  message?: string;
  data: AdminUserReport;
}

export interface UserReportsParams {
  status?: UserReportStatus;
  page?: number;
  per_page?: number;
}

export const ADMIN_USER_REPORTS_QUERY_KEY = ['admin', 'user-reports'] as const;

export async function fetchUserReports(params: UserReportsParams): Promise<UserReportsData> {
  const query = new URLSearchParams();
  if (params.status) query.set('status', params.status);
  if (params.page) query.set('page', String(params.page));
  if (params.per_page) query.set('per_page', String(params.per_page));

  const qs = query.toString();
  const response = await api.get<UserReportsResponse>(
    `/admin/user-reports${qs ? `?${qs}` : ''}`,
  );

  return response.data.data;
}

export function useUserReports(params: UserReportsParams) {
  return useQuery({
    queryKey: [...ADMIN_USER_REPORTS_QUERY_KEY, 'list', params],
    queryFn: () => fetchUserReports(params),
    placeholderData: keepPreviousData,
    staleTime: 30_000,
    refetchOnWindowFocus: false,
    retry: 1,
  });
}

/**
 * The total report count for the User Reports tab badge. The list endpoint
 * already reports the server's exact total, so no separate count route is
 * needed.
 */
export function useUserReportCount() {
  return useQuery({
    queryKey: [...ADMIN_USER_REPORTS_QUERY_KEY, 'count'],
    queryFn: async () => (await fetchUserReports({ per_page: 1 })).pagination.total,
    staleTime: 30_000,
  });
}

export async function fetchUserReport(id: number): Promise<AdminUserReport> {
  const response = await api.get<UserReportResponse>(`/admin/user-reports/${id}`);
  return response.data.data;
}

export function useUserReport(id: number | null) {
  return useQuery({
    queryKey: [...ADMIN_USER_REPORTS_QUERY_KEY, 'detail', id],
    queryFn: () => fetchUserReport(id as number),
    enabled: id !== null,
    staleTime: 0,
    refetchOnWindowFocus: false,
    retry: 1,
  });
}

export async function fetchUserReportEvidence(id: number): Promise<Blob> {
  const response = await api.get<Blob>(`/admin/user-reports/${id}/evidence`, {
    responseType: 'blob',
  });
  return response.data;
}

export async function dismissUserReport(id: number, adminNote?: string): Promise<AdminUserReport> {
  const response = await api.post<UserReportResponse>(`/admin/user-reports/${id}/dismiss`, {
    admin_note: adminNote?.trim() || null,
  });
  return response.data.data;
}

export async function deactivateFromUserReport(
  id: number,
  reason: string,
): Promise<AdminUserReport> {
  const response = await api.post<UserReportResponse>(
    `/admin/user-reports/${id}/deactivate`,
    { reason },
  );
  return response.data.data;
}

function useInvalidateUserReports() {
  const queryClient = useQueryClient();

  return () => {
    void queryClient.invalidateQueries({ queryKey: ADMIN_USER_REPORTS_QUERY_KEY });
    void queryClient.invalidateQueries({ queryKey: ['admin', 'users'] });
    void queryClient.invalidateQueries({ queryKey: ['admin', 'activities'] });
  };
}

export function useDismissUserReport() {
  const invalidate = useInvalidateUserReports();

  return useMutation({
    mutationFn: ({ id, adminNote }: { id: number; adminNote?: string }) =>
      dismissUserReport(id, adminNote),
    onSuccess: invalidate,
  });
}

export function useDeactivateFromUserReport() {
  const invalidate = useInvalidateUserReports();

  return useMutation({
    mutationFn: ({ id, reason }: { id: number; reason: string }) =>
      deactivateFromUserReport(id, reason),
    onSuccess: invalidate,
  });
}
