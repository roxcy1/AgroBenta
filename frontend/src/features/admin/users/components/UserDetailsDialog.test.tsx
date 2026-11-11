/** @vitest-environment jsdom */
import { afterEach, describe, expect, it, vi } from 'vitest';
import { cleanup, fireEvent, render, screen } from '@testing-library/react';
import type { AdminUser } from '../api/useUsers';
import { formatDateTime } from '../../../../lib/format';
import UserDetailsDialog from './UserDetailsDialog';

const user: AdminUser = {
  id: 276,
  name: 'Amina Santos',
  email: 'amina@example.test',
  role: 'user',
  seller_capability: 'buyer',
  email_verified_at: '2026-11-06T18:17:00.000000Z',
  created_at: '2026-11-05T18:17:00.000000Z',
  updated_at: '2026-11-07T23:39:00.000000Z',
};

afterEach(() => cleanup());

describe('UserDetailsDialog', () => {
  it('renders dynamic account fields in the four requested sections', () => {
    render(<UserDetailsDialog user={user} verificationStatus="approved" onClose={vi.fn()} />);

    expect(screen.getByRole('heading', { name: 'Amina Santos' })).not.toBeNull();
    expect(screen.getByText('Account details for this user.')).not.toBeNull();
    expect(screen.getByText('#276')).not.toBeNull();
    expect(screen.getByText('Summary')).not.toBeNull();
    expect(screen.getByText('Account')).not.toBeNull();
    expect(screen.getByText('Contact')).not.toBeNull();
    expect(screen.getByText('Record')).not.toBeNull();
    expect(screen.getByText('Approved')).not.toBeNull();
    expect(screen.getByText('User')).not.toBeNull();
    expect(screen.getByText('Buyer')).not.toBeNull();
    expect(screen.getByText('Email verification status')).not.toBeNull();
    expect(screen.getByText(formatDateTime(user.email_verified_at!))).not.toBeNull();
    expect(screen.getByText('amina@example.test')).not.toBeNull();
    expect(screen.getByText(formatDateTime(user.created_at))).not.toBeNull();
    expect(screen.getByText(formatDateTime(user.updated_at))).not.toBeNull();
    expect(screen.queryByText('Account Status')).toBeNull();
  });

  it('preserves unverified state and header, footer, Escape and backdrop close behavior', () => {
    const onClose = vi.fn();
    const { container } = render(
      <UserDetailsDialog user={{ ...user, email_verified_at: null }} verificationStatus={null} onClose={onClose} />,
    );

    expect(screen.getByText('Not verified')).not.toBeNull();
    expect(screen.getByText('—')).not.toBeNull();

    fireEvent.click(screen.getByRole('button', { name: 'Close user details' }));
    fireEvent.click(screen.getByRole('button', { name: /^Close$/ }));
    fireEvent.keyDown(window, { key: 'Escape' });
    fireEvent.click(container.querySelector('.user-details-overlay')!);

    expect(onClose).toHaveBeenCalledTimes(4);
  });
});
