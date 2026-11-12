/** @vitest-environment jsdom */
import { afterEach, describe, expect, it, vi } from 'vitest';
import { cleanup, fireEvent, render, screen } from '@testing-library/react';
import type { Transaction } from '../api/useTransactions';
import { formatDateTime, formatPeso } from '../../../../lib/format';
import TransactionDetailDialog from './TransactionDetailDialog';

const transaction: Transaction = {
  id: 42,
  buyer: { id: 1, name: 'Ana Buyer', email: 'ana@example.test' },
  seller: { id: 2, name: 'Ben Seller', email: 'ben@example.test' },
  listing: { id: 17, livestock_type: 'cattle', breed: 'Native Cattle' },
  quantity: 2,
  total_amount: '25000.00',
  status: 'pending',
  created_at: '2026-10-01T08:30:00.000000Z',
  updated_at: '2026-10-02T09:00:00.000000Z',
};

afterEach(() => cleanup());

describe('TransactionDetailDialog', () => {
  it('keeps transaction details dynamic across the shared detail cards', () => {
    render(<TransactionDetailDialog transaction={transaction} livestockTypes={[]} onClose={vi.fn()} />);

    expect(screen.getByRole('heading', { name: 'Transaction #42' })).not.toBeNull();
    expect(screen.getByText('Summary')).not.toBeNull();
    expect(screen.getByText('Parties')).not.toBeNull();
    expect(screen.getByText('Livestock')).not.toBeNull();
    expect(screen.getByText('Record')).not.toBeNull();
    expect(screen.getByText('Ana Buyer (ana@example.test)')).not.toBeNull();
    expect(screen.getByText('Ben Seller (ben@example.test)')).not.toBeNull();
    expect(screen.getByText('Native Cattle')).not.toBeNull();
    expect(screen.getByText(formatPeso(transaction.total_amount))).not.toBeNull();
    expect(screen.getByText(formatDateTime(transaction.created_at))).not.toBeNull();
    expect(screen.getByText(formatDateTime(transaction.updated_at))).not.toBeNull();
    expect(screen.getByText('Pending')).not.toBeNull();
  });

  it('preserves header, footer, Escape, and backdrop close behavior', () => {
    const onClose = vi.fn();
    const { container } = render(
      <TransactionDetailDialog transaction={transaction} livestockTypes={[]} onClose={onClose} />,
    );

    fireEvent.click(screen.getByRole('button', { name: 'Close transaction details' }));
    fireEvent.click(screen.getByRole('button', { name: /^Close$/ }));
    fireEvent.keyDown(window, { key: 'Escape' });
    fireEvent.click(container.querySelector('.listing-details-overlay')!);

    expect(onClose).toHaveBeenCalledTimes(4);
  });
});
