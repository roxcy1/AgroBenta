/**
 * Parse a URL query parameter as a positive integer id.
 *
 * Deep links carry ids as strings, but the underlying API and React Query keys
 * use numbers. Anything that is not a strictly positive integer is treated as
 * absent so a malformed link degrades to the normal page instead of requesting
 * `/records/NaN`.
 */
export function parsePositiveInt(value: string | null | undefined): number | null {
  if (value === null || value === undefined) return null;

  const trimmed = value.trim();
  if (!/^\d+$/.test(trimmed)) return null;

  const parsed = Number(trimmed);
  if (!Number.isInteger(parsed) || parsed <= 0) return null;

  return parsed;
}

export type DeepLinkEntity = 'Listing' | 'Transaction' | 'User';

export type DeepLinkStatus = 'inactive' | 'loading' | 'missing' | 'ready';

export interface DeepLinkedRecord<T> {
  record: T | null;
  status: DeepLinkStatus;
  message: string | null;
}

export function resolveDeepLinkedRecord<T>(options: {
  entity: DeepLinkEntity;
  id: number | null;
  dismissedId: number | null;
  record: T | undefined;
  isError: boolean;
}): DeepLinkedRecord<T> {
  const { entity, id, dismissedId, record, isError } = options;

  if (id === null || id === dismissedId) {
    return { record: null, status: 'inactive', message: null };
  }

  if (record !== undefined) {
    return { record, status: 'ready', message: null };
  }

  if (isError) {
    return {
      record: null,
      status: 'missing',
      message: `${entity} #${id} could not be loaded. It may have been removed.`,
    };
  }

  return { record: null, status: 'loading', message: null };
}
