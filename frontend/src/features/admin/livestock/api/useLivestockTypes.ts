import { useQuery } from '@tanstack/react-query';
import api from '../../../../lib/api';

export interface LivestockTypeOption {
  value: string;
  label: string;
  breeds: string[];
}

export function livestockTypeLabel(
  value: string | null | undefined,
  types: LivestockTypeOption[] | undefined,
): string {
  if (!value) return '';
  return types?.find((type) => type.value === value.toLowerCase())?.label ?? value;
}

interface LivestockTypeResponse {
  data: LivestockTypeOption[];
}

export async function fetchLivestockTypes(): Promise<LivestockTypeOption[]> {
  const response = await api.get<LivestockTypeResponse>('/livestock-types');
  return response.data.data;
}

export function listingTypeOptions(
  types: LivestockTypeOption[] | undefined,
): LivestockTypeOption[] {
  return [{ value: '', label: 'All Types', breeds: [] }, ...(types ?? [])];
}

// Avoid duplicate catalog requests while a retry is already in flight.
export function requestLivestockTypesRefetch(
  isFetching: boolean,
  refetch: () => Promise<unknown>,
): void {
  if (!isFetching) {
    void refetch();
  }
}

export function useLivestockTypes() {
  return useQuery({
    queryKey: ['livestock-types'],
    queryFn: fetchLivestockTypes,
    staleTime: 30_000,
    refetchOnWindowFocus: false,
    retry: 1,
  });
}
