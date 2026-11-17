import { afterEach, describe, expect, it, vi } from 'vitest';
import type { AxiosResponse } from 'axios';
import api from '../../../../lib/api';
import { fetchListing, reconcileListingInventory, type Listing } from './useListings';

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
    total_quantity: 4,
    reserved_quantity: 0,
    platform_sold_quantity: 0,
    sold_quantity: 0,
    available_quantity: 4,
    externally_sold_quantity: 0,
    inventory_reconciliation_required: false,
    legacy_quantity_snapshot: null,
    asking_price: '50000.00',
    location: 'Batangas',
    health_status: 'healthy',
    vaccination: 'complete',
    short_description: 'Healthy cattle',
    additional_notes: null,
    photos: ['http://localhost/storage/listings/' + id + '/a.jpg'],
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

describe('reconcileListingInventory', () => {
  afterEach(() => {
    vi.restoreAllMocks();
  });

  it('posts the evidence-backed inventory reconciliation to the admin route', async () => {
    const input = {
      verified_physical_quantity: 3,
      verified_externally_sold_quantity: 1,
      accounted_transaction_ids: [8, 9],
      reason: 'Seller verified the remaining animals.',
      evidence: 'Signed inventory sheet.',
    };
    const response = {
      listing: makeListing(5),
      reconciliation: {
        id: 2,
        listing_id: 5,
        admin: { id: 1, name: 'Admin' },
        verified_physical_quantity: 3,
        verified_pending_quantity: 2,
        verified_completed_quantity: 3,
        verified_externally_sold_quantity: 1,
        verified_total_quantity: 9,
        verified_available_quantity: 3,
        accounted_transaction_ids: [8, 9],
        reason: input.reason,
        evidence: input.evidence,
        created_at: '2026-11-14T00:00:00.000000Z',
      },
    };
    const spy = vi.spyOn(api, 'post').mockResolvedValueOnce({
      data: { success: true, message: 'ok', data: response },
    } as unknown as AxiosResponse);

    await expect(reconcileListingInventory(5, input)).resolves.toEqual(response);
    expect(spy.mock.calls[0][0]).toBe('/admin/listings/5/inventory/reconcile');
    expect(spy.mock.calls[0][1]).toEqual(input);
  });
});
