import { afterEach, describe, expect, it, vi } from 'vitest';
import type { AxiosResponse } from 'axios';
import api from '../../../../lib/api';
import {
  fetchLivestockTypes,
  listingTypeOptions,
  requestLivestockTypesRefetch,
} from './useLivestockTypes';

describe('livestock type catalog', () => {
  afterEach(() => vi.restoreAllMocks());

  it('reads the backend-owned catalog endpoint', async () => {
    const types = [
      { value: 'cattle', label: 'Cattle' },
      { value: 'carabao', label: 'Carabao' },
      { value: 'goat', label: 'Goat' },
      { value: 'swine', label: 'Swine' },
    ];
    const spy = vi.spyOn(api, 'get').mockResolvedValueOnce({
      data: { data: types },
    } as unknown as AxiosResponse);

    await expect(fetchLivestockTypes()).resolves.toEqual(types);
    expect(spy).toHaveBeenCalledWith('/livestock-types');
  });

  it('keeps All Types and exposes only backend values', () => {
    expect(listingTypeOptions([{ value: 'swine', label: 'Swine' }])).toEqual([
      { value: '', label: 'All Types' },
      { value: 'swine', label: 'Swine' },
    ]);
  });

  it('does not start a duplicate catalog request while a retry is in flight', () => {
    const refetch = vi.fn<() => Promise<unknown>>().mockResolvedValue(undefined);

    requestLivestockTypesRefetch(false, refetch);
    requestLivestockTypesRefetch(true, refetch);

    expect(refetch).toHaveBeenCalledTimes(1);
  });
});
