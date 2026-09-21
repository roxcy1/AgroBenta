import { useQuery } from '@tanstack/react-query';
import api from '../../../../lib/api';

export interface ActivityUser {
  id: number;
  name: string;
  email: string;
}

export interface Activity {
  id: number;
  user: ActivityUser | null;
  action: string;
  description: string | null;
  metadata: Record<string, unknown> | null;
  created_at: string;
  updated_at: string;
}

export interface ActivitiesPagination {
  current_page: number;
  last_page: number;
  per_page: number;
  total: number;
}

export interface ActivitiesData {
  activities: Activity[];
  pagination: ActivitiesPagination;
}

interface ActivitiesResponse {
  success: boolean;
  data: ActivitiesData;
}

export interface ActivitiesParams {
  search?: string;
  action?: string;
  user_id?: number;
  date_from?: string;
  date_to?: string;
  page?: number;
  per_page?: number;
}

async function fetchActivities(params: ActivitiesParams): Promise<ActivitiesData> {
  const query = new URLSearchParams();
  if (params.search) query.set('search', params.search);
  if (params.action) query.set('action', params.action);
  if (params.user_id) query.set('user_id', String(params.user_id));
  if (params.date_from) query.set('date_from', params.date_from);
  if (params.date_to) query.set('date_to', params.date_to);
  if (params.page) query.set('page', String(params.page));
  if (params.per_page) query.set('per_page', String(params.per_page));

  const qs = query.toString();
  const url = `/admin/activities${qs ? `?${qs}` : ''}`;

  const response = await api.get<ActivitiesResponse>(url);
  return response.data.data;
}

export function useActivities(params: ActivitiesParams) {
  return useQuery({
    queryKey: ['admin', 'activities', params],
    queryFn: () => fetchActivities(params),
    staleTime: 30_000,
    refetchOnWindowFocus: false,
    retry: 1,
  });
}
