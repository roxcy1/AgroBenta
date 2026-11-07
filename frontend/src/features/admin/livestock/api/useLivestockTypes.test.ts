import { afterEach, describe, expect, it, vi } from 'vitest';
import type { AxiosResponse } from 'axios';
import api from '../../../../lib/api';
import {
  fetchLivestockTypes,
  listingTypeOptions,
  livestockTypeLabel,
  requestLivestockTypesRefetch,
} from './useLivestockTypes';

describe('livestock type catalog', () => {
  afterEach(() => vi.restoreAllMocks());

  it('reads the backend-owned catalog endpoint', async () => {
    const types = [
      { value: 'cattle', label: 'Cattle', breeds: ['Brahman'] },
      { value: 'carabao', label: 'Carabao', breeds: ['Murrah'] },
      { value: 'goat', label: 'Goat', breeds: ['Boer'] },
      { value: 'swine', label: 'Swine', breeds: ['Landrace'] },
      { value: 'chicken', label: 'Chicken', breeds: ['Broiler'] },
    ];
    const spy = vi.spyOn(api, 'get').mockResolvedValueOnce({
      data: { data: types },
    } as unknown as AxiosResponse);

    await expect(fetchLivestockTypes()).resolves.toEqual(types);
    expect(spy).toHaveBeenCalledWith('/livestock-types');
  });

  it('keeps All Types and exposes only backend values', () => {
    expect(listingTypeOptions([{ value: 'swine', label: 'Swine', breeds: ['Landrace'] }])).toEqual([
      { value: '', label: 'All Types', breeds: [] },
      { value: 'swine', label: 'Swine', breeds: ['Landrace'] },
    ]);
  });

  it('labels a known category and preserves unknown stored values', () => {
    const types = [{ value: 'chicken', label: 'Chicken', breeds: ['Broiler'] }];
    expect(livestockTypeLabel('chicken', types)).toBe('Chicken');
    expect(livestockTypeLabel('legacy type', types)).toBe('legacy type');
  });

  it('does not start a duplicate catalog request while a retry is in flight', () => {
    const refetch = vi.fn<() => Promise<unknown>>().mockResolvedValue(undefined);

    requestLivestockTypesRefetch(false, refetch);
    requestLivestockTypesRefetch(true, refetch);

    expect(refetch).toHaveBeenCalledTimes(1);
  });
});
