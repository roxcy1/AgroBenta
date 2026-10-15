import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import api from '../../../../lib/api';

export interface Setting {
  key: string;
  value: string;
  group: string;
  label: string;
  description: string | null;
}

export type SettingsData = Record<string, Setting[]>;

interface SettingsResponse {
  success: boolean;
  data: SettingsData;
}

interface UpdateSettingsResponse {
  success: boolean;
  message: string;
  data: SettingsData;
  updated: string[];
  rejected: string[];
}

/** The React Query key for the settings map, shared by read and write. */
export const SETTINGS_QUERY_KEY = ['admin', 'settings'] as const;

async function fetchSettings(): Promise<SettingsData> {
  const response = await api.get<SettingsResponse>('/admin/settings');
  return response.data.data;
}

async function updateSettings(input: Record<string, string>): Promise<UpdateSettingsResponse> {
  const response = await api.put<UpdateSettingsResponse>('/admin/settings', input);
  return response.data;
}

export function useSettings() {
  return useQuery({
    queryKey: SETTINGS_QUERY_KEY,
    queryFn: fetchSettings,
    staleTime: 60_000,
    refetchOnWindowFocus: false,
    retry: 1,
  });
}

export function useUpdateSettings() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: updateSettings,
    onSuccess: (result) => {
      // The response carries the full, persisted settings map, so reconcile the
      // cached query with it directly instead of triggering a second GET. The
      // form's originals then reflect exactly what the server stored.
      queryClient.setQueryData(SETTINGS_QUERY_KEY, result.data);
    },
  });
}
