import { afterEach, describe, expect, it, vi } from 'vitest';
import type { AxiosResponse } from 'axios';
import api from '../../../../lib/api';
import { fetchListing, type Listing } from './useListings';

function makeListing(id: number): Listing {
  return {
    id,
    seller: { id: 3, name: 'Seller', email: 'seller@example.com' },
    livestock_type: 'cattle',
    breed: 'Brahman',
    age_value: 2,
    age_unit: 'years',
    gender: 'male',
    weight_value: 450,
    weight_unit: 'kg',
    quantity: 4,
    asking_price: '50000.00',
    location: 'Batangas',
    health_status: 'healthy',
    vaccination: 'complete',
    short_description: 'Healthy cattle',
    additional_notes: null,
    status: 'active',
    admin_note: null,
    created_at: '2026-10-01T00:00:00.000000Z',
    updated_at: '2026-10-01T00:00:00.000000Z',
  };
}

describe('fetchListing', () => {
  afterEach(() => {
    vi.restoreAllMocks();
  });

  it('requests the single listing by id and returns the record', async () => {
    const spy = vi.spyOn(api, 'get').mockResolvedValueOnce({
      data: { success: true, data: makeListing(5) },
    } as unknown as AxiosResponse);

    const listing = await fetchListing(5);

    expect(spy.mock.calls[0][0]).toBe('/admin/listings/5');
    expect(listing.id).toBe(5);
  });
});
