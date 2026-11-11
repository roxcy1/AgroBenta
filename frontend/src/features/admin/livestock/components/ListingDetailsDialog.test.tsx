/** @vitest-environment jsdom */
import { afterEach, describe, expect, it, vi } from 'vitest';
import { cleanup, fireEvent, render, screen } from '@testing-library/react';
import type { Listing } from '../api/useListings';
import ListingDetailsDialog from './ListingDetailsDialog';

const listing: Listing = {
  id: 116,
  seller: { id: 42, name: 'Amina Santos', email: 'amina@example.test' },
  livestock_type: 'cattle',
  breed: 'Philippine Native Cattle',
  age_value: 12,
  age_unit: 'month',
  gender: 'female',
  weight_value: 12,
  weight_unit: 'lb',
  quantity: 2,
  asking_price: '12500.00',
  location: 'Poblacion, Trinidad',
  health_status: 'healthy',
  vaccination: 'up_to_date',
  short_description: 'Healthy listing description',
  additional_notes: 'Additional seller notes',
  photos: ['https://images.example.test/listing-1.jpg', 'https://images.example.test/listing-2.jpg'],
  status: 'draft',
  admin_note: null,
  created_at: '2026-10-01T08:30:00.000000Z',
  updated_at: '2026-10-02T09:00:00.000000Z',
};

afterEach(() => cleanup());

describe('ListingDetailsDialog', () => {
  it('shows the current listing, its real photo, and all preserved details', () => {
    render(<ListingDetailsDialog listing={listing} livestockTypes={[]} onClose={vi.fn()} />);

    expect(screen.getByRole('heading', { name: 'Listing #116' })).not.toBeNull();
    expect(screen.getByText('Full details recorded for this listing.')).not.toBeNull();
    expect(screen.getByText('Photo 1 of 2')).not.toBeNull();
    expect(screen.getByRole('link', { name: 'Open full size' }).getAttribute('href'))
      .toBe(listing.photos[0]);
    expect(screen.getByRole('img', { name: 'Listing #116: Photo 1 of 2' }).getAttribute('src'))
      .toBe(listing.photos[0]);
    expect(screen.getByText('Philippine Native Cattle')).not.toBeNull();
    expect(screen.getByText('12 month')).not.toBeNull();
    expect(screen.getByText('Poblacion, Trinidad')).not.toBeNull();
    expect(screen.getByText('Healthy listing description')).not.toBeNull();
    expect(screen.getByText('Additional seller notes')).not.toBeNull();
    expect(screen.getByText('Amina Santos')).not.toBeNull();
  });

  it('keeps multi-photo navigation and close controls working', () => {
    const onClose = vi.fn();
    const { container } = render(
      <ListingDetailsDialog listing={listing} livestockTypes={[]} onClose={onClose} />,
    );

    fireEvent.click(screen.getByRole('button', { name: 'Next photo' }));
    expect(screen.getByText('Photo 2 of 2')).not.toBeNull();
    expect(screen.getByRole('img', { name: 'Listing #116: Photo 2 of 2' }).getAttribute('src'))
      .toBe(listing.photos[1]);

    fireEvent.click(screen.getByRole('button', { name: 'Close listing details' }));
    fireEvent.click(screen.getByRole('button', { name: /^Close$/ }));
    fireEvent.keyDown(window, { key: 'Escape' });
    fireEvent.click(container.querySelector('.listing-details-overlay')!);

    expect(onClose).toHaveBeenCalledTimes(4);
  });

  it('omits photo navigation arrows for a single image and preserves empty listings', () => {
    const singlePhotoListing = { ...listing, photos: [listing.photos[0]] };
    const { rerender } = render(
      <ListingDetailsDialog listing={singlePhotoListing} livestockTypes={[]} onClose={vi.fn()} />,
    );

    expect(screen.queryByRole('button', { name: 'Previous photo' })).toBeNull();
    expect(screen.queryByRole('button', { name: 'Next photo' })).toBeNull();
    expect(screen.getByText('Photo 1 of 1')).not.toBeNull();

    rerender(
      <ListingDetailsDialog listing={{ ...listing, photos: [] }} livestockTypes={[]} onClose={vi.fn()} />,
    );
    expect(screen.getByText('No photos uploaded')).not.toBeNull();
    expect(screen.queryByRole('link', { name: 'Open full size' })).toBeNull();
  });
});
