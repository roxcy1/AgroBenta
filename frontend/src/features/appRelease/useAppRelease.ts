import { useQuery } from '@tanstack/react-query';
import api from '../../lib/api';

/** `GET /api/app-release` — the latest published Android build. */
export interface AppRelease {
  version_name: string;
  version_code: number;
  download_url: string;
  size_bytes: number;
  sha256: string;
  notes: string | null;
  published_at: string;
}

interface AppReleaseResponse {
  success: boolean;
  message: string;
  data: AppRelease | null;
}

/** The latest app release, or null before one is published. Public endpoint. */
export function useAppRelease() {
  return useQuery({
    queryKey: ['app-release'],
    queryFn: async () => {
      const response = await api.get<AppReleaseResponse>('/app-release');
      return response.data.data;
    },
    staleTime: 5 * 60_000,
  });
}

/** "48.2 MB" from a byte count. */
export function formatReleaseSize(bytes: number): string {
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
}
