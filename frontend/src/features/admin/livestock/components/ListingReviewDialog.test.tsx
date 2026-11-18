/** @vitest-environment jsdom */
import { afterEach, describe, expect, it, vi } from 'vitest';
import { cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react';
import { QueryClient, QueryClientProvider, useQuery } from '@tanstack/react-query';
import type { AxiosResponse } from 'axios';
import api from '../../../../lib/api';
import type { Listing } from '../api/useListings';
import { moderationOptionsFor } from './listingModeration';
import ListingReviewDialog from './ListingReviewDialog';

const listing: Listing = {
  id: 19,
  seller: { id: 4, name: 'Seller', email: 'seller@example.test' },
  livestock_type: 'cattle',
  breed: 'Brahman',
  age_value: 2,
  age_unit: 'years',
  gender: 'female',
  weight_value: 350,
  weight_unit: 'kg',
  quantity: 4,
  total_quantity: 6,
  reserved_quantity: 1,
  platform_sold_quantity: 1,
  sold_quantity: 1,
  available_quantity: 4,
  externally_sold_quantity: 0,
  inventory_reconciliation_required: false,
  legacy_quantity_snapshot: null,
  asking_price: '40000.00',
  location: 'Poblacion',
  health_status: 'healthy',
  vaccination: 'complete',
  short_description: 'Healthy cattle',
  additional_notes: null,
  photos: [],
  status: 'inactive',
  admin_note: null,
  created_at: '2026-11-01T00:00:00.000Z',
  updated_at: '2026-11-01T00:00:00.000Z',
};

afterEach(() => {
  cleanup();
  vi.restoreAllMocks();
});

function renderDialog(
  action: 'approve' | 'reject' | 'deactivate' | 'reactivate',
  onClose = vi.fn(),
) {
  const queryClient = new QueryClient({
    defaultOptions: { queries: { retry: false }, mutations: { retry: false } },
  });
  const option = action === 'approve' || action === 'reject'
    ? moderationOptionsFor('pending').find((item) => item.action === action)!
    : moderationOptionsFor(action === 'deactivate' ? 'active' : 'inactive', listing)
        .find((item) => item.action === action)!;

  return {
    onClose,
    ...render(
      <QueryClientProvider client={queryClient}>
        <ListingReviewDialog
          listing={{ ...listing, status: action === 'approve' || action === 'reject' ? 'pending' : action === 'deactivate' ? 'active' : 'inactive' }}
          livestockTypes={[]}
          option={option}
          onClose={onClose}
        />
      </QueryClientProvider>,
    ),
  };
}

describe('ListingReviewDialog Reactivate action', () => {
  it('asks for confirmation and cancellation does not call the API', () => {
    const post = vi.spyOn(api, 'post');
    const onClose = vi.fn();
    renderDialog('reactivate', onClose);

    expect(screen.getByRole('heading', { name: 'Reactivate Listing' })).not.toBeNull();
    expect(screen.getByText(/become active and visible in the Marketplace again/i)).not.toBeNull();
    fireEvent.click(screen.getByRole('button', { name: 'Cancel' }));

    expect(post).not.toHaveBeenCalled();
    expect(onClose).toHaveBeenCalledOnce();
  });

  it('confirms through the existing mutation and refreshes active listing queries', async () => {
    const post = vi.spyOn(api, 'post').mockResolvedValue({
      data: {
        success: true,
        message: 'Listing reactivated successfully.',
        data: { ...listing, status: 'active' },
      },
    } as unknown as AxiosResponse);
    const fetchActiveListings = vi.fn().mockResolvedValue(null);
    const onClose = vi.fn();

    // Use an observed query to verify that mutation invalidation refreshes the
    // listing views, including the Active Listings filter.
    const queryClient = new QueryClient({
      defaultOptions: { queries: { retry: false }, mutations: { retry: false } },
    });
    function ActiveListingsProbe() {
      useQuery({ queryKey: ['admin', 'listings', { status: 'active' }], queryFn: fetchActiveListings });
      return null;
    }
    const option = moderationOptionsFor('inactive', listing).find((item) => item.action === 'reactivate')!;
    render(
      <QueryClientProvider client={queryClient}>
        <ActiveListingsProbe />
        <ListingReviewDialog listing={listing} livestockTypes={[]} option={option} onClose={onClose} />
      </QueryClientProvider>,
    );

    fireEvent.click(screen.getByRole('button', { name: 'Reactivate' }));

    await waitFor(() => expect(post).toHaveBeenCalledWith('/admin/listings/19/reactivate', {}));
    await waitFor(() => expect(onClose).toHaveBeenCalledOnce());
    await waitFor(() => expect(fetchActiveListings).toHaveBeenCalledTimes(2));
  });

  it('disables confirmation while pending to prevent duplicate requests', async () => {
    let resolveRequest!: (value: AxiosResponse) => void;
    const post = vi.spyOn(api, 'post').mockReturnValueOnce(
      new Promise((resolve) => { resolveRequest = resolve; }),
    );
    renderDialog('reactivate');

    fireEvent.click(screen.getByRole('button', { name: 'Reactivate' }));
    const pendingButton = await screen.findByRole('button', { name: 'Working…' });
    fireEvent.click(pendingButton);

    expect(pendingButton.hasAttribute('disabled')).toBe(true);
    expect(post).toHaveBeenCalledOnce();

    resolveRequest({
      data: { success: true, message: 'ok', data: { ...listing, status: 'active' } },
    } as unknown as AxiosResponse);
  });

  it('shows the backend eligibility conflict without closing the dialog', async () => {
    vi.spyOn(api, 'post').mockRejectedValueOnce({
      response: {
        status: 409,
        data: { message: 'Only an administrator-deactivated listing can be restored.' },
      },
    });
    const onClose = vi.fn();
    renderDialog('reactivate', onClose);

    fireEvent.click(screen.getByRole('button', { name: 'Reactivate' }));

    expect(await screen.findByText('Only an administrator-deactivated listing can be restored.')).not.toBeNull();
    expect(onClose).not.toHaveBeenCalled();
  });

  it.each([
    [403, { message: 'Forbidden.' }, 'You do not have permission to moderate listings.'],
    [404, { message: 'Not found.' }, 'This listing no longer exists.'],
    [422, { message: 'Invalid request.', errors: { listing: ['The listing is not eligible.'] } }, 'The listing is not eligible.'],
  ] as const)('shows clear feedback for HTTP %s', async (status, data, expectedMessage) => {
    vi.spyOn(api, 'post').mockRejectedValueOnce({ response: { status, data } });
    renderDialog('reactivate');

    fireEvent.click(screen.getByRole('button', { name: 'Reactivate' }));

    expect(await screen.findByText(expectedMessage)).not.toBeNull();
  });
});

describe('existing listing moderation actions', () => {
  it.each([
    ['approve', '/admin/listings/19/approve'],
    ['reject', '/admin/listings/19/reject'],
    ['deactivate', '/admin/listings/19/deactivate'],
  ] as const)('%s still calls its existing endpoint', async (action, endpoint) => {
    const post = vi.spyOn(api, 'post').mockResolvedValueOnce({
      data: { success: true, message: 'ok', data: listing },
    } as unknown as AxiosResponse);
    renderDialog(action);

    fireEvent.click(screen.getByRole('button', { name: action === 'approve' ? 'Approve' : action === 'reject' ? 'Reject' : 'Deactivate' }));

    await waitFor(() => expect(post.mock.calls[0]?.[0]).toBe(endpoint));
  });
});
