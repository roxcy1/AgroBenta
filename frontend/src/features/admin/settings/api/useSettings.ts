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
    queryKey: ['admin', 'settings'],
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
    onSuccess: () => {
      void queryClient.invalidateQueries({ queryKey: ['admin', 'settings'] });
    },
  });
}
