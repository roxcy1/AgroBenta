import { keepPreviousData, useQuery } from '@tanstack/react-query';
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
  action?: string | string[];
  actions?: string[];
  user_id?: number;
  date_from?: string;
  date_to?: string;
  page?: number;
  per_page?: number;
}

export interface ActivitySummary {
  total_activities: number;
  active_actors: number;
  moderation_actions: number;
  configuration_changes: number;
  window: string;
  since: string;
  until: string;
}

export interface ActivitySummaryResponse {
  success: boolean;
  data: ActivitySummary;
}

export async function fetchActivities(params: ActivitiesParams): Promise<ActivitiesData> {
  const query = new URLSearchParams();
  if (params.search) query.set('search', params.search);
  if (Array.isArray(params.actions) && params.actions.length > 0) {
    params.actions.forEach((action) => {
      query.append('actions[]', action);
    });
  } else if (Array.isArray(params.action) && params.action.length > 0) {
    params.action.forEach((action) => {
      query.append('actions[]', action);
    });
  } else if (typeof params.action === 'string' && params.action) {
    query.set('action', params.action);
  }
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

export async function fetchActivitySummary(): Promise<ActivitySummary> {
  const response = await api.get<ActivitySummaryResponse>('/admin/activities/summary');
  return response.data.data;
}

export function useActivities(params: ActivitiesParams) {
  return useQuery({
    queryKey: ['admin', 'activities', params],
    queryFn: () => fetchActivities(params),
    placeholderData: keepPreviousData,
    staleTime: 30_000,
    refetchOnWindowFocus: false,
    retry: 1,
  });
}

export function useActivitySummary() {
  return useQuery({
    queryKey: ['admin', 'activities', 'summary'],
    queryFn: fetchActivitySummary,
    staleTime: 30_000,
    refetchOnWindowFocus: false,
    retry: 1,
  });
}
