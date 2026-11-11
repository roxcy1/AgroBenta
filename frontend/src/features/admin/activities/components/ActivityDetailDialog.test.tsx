/** @vitest-environment jsdom */
import { afterEach, describe, expect, it, vi } from 'vitest';
import { cleanup, fireEvent, render, screen } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import type { Activity } from '../api/useActivities';
import { activityActionLabel, formatActivityTimestamp } from '../activityFormat';
import ActivityDetailDialog from './ActivityDetailDialog';

const activity: Activity = {
  id: 89,
  user: { id: 3, name: 'Admin User', email: 'admin@example.test' },
  action: 'listing_approved',
  description: 'Approved a cattle listing',
  metadata: {
    target_type: 'listing',
    target_id: 17,
    changes: { status: { from: 'pending', to: 'active' } },
    context: { quantity: 2 },
  },
  created_at: '2026-10-01T08:30:00.000000Z',
  updated_at: '2026-10-01T08:30:00.000000Z',
};

afterEach(() => cleanup());

describe('ActivityDetailDialog', () => {
  it('retains dynamic activity details in the shared modal layout', () => {
    render(
      <MemoryRouter>
        <ActivityDetailDialog activity={activity} onClose={vi.fn()} />
      </MemoryRouter>,
    );

    expect(screen.getByRole('heading', { name: 'Activity #89' })).not.toBeNull();
    expect(screen.getByText('Approved a cattle listing')).not.toBeNull();
    expect(screen.getByText('Summary')).not.toBeNull();
    expect(screen.getByText('Changes')).not.toBeNull();
    expect(screen.getByText('Context')).not.toBeNull();
    expect(screen.getByText('Recorded')).not.toBeNull();
    expect(screen.getByText('Admin User')).not.toBeNull();
    expect(screen.getAllByText('Listing #17')).toHaveLength(2);
    expect(screen.getByText('pending')).not.toBeNull();
    expect(screen.getByText('active')).not.toBeNull();
    expect(screen.getAllByText(formatActivityTimestamp(activity.created_at))).toHaveLength(2);
    expect(screen.getByText(activityActionLabel(activity.action))).not.toBeNull();
  });

  it('preserves header, footer, Escape, and backdrop close behavior', () => {
    const onClose = vi.fn();
    const { container } = render(
      <MemoryRouter>
        <ActivityDetailDialog activity={activity} onClose={onClose} />
      </MemoryRouter>,
    );

    fireEvent.click(screen.getByRole('button', { name: 'Close activity details' }));
    fireEvent.click(screen.getByRole('button', { name: /^Close$/ }));
    fireEvent.keyDown(window, { key: 'Escape' });
    fireEvent.click(container.querySelector('.listing-details-overlay')!);

    expect(onClose).toHaveBeenCalledTimes(4);
  });
});
