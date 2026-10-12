import { afterEach, describe, expect, it, vi } from 'vitest';
import type { AxiosResponse } from 'axios';
import api from '../../../../lib/api';
import {
  fetchAllTransactions,
  type Transaction,
  type TransactionsPagination,
} from './useTransactions';

function makeTransaction(id: number): Transaction {
  return {
    id,
    buyer: { id: 1, name: 'Buyer', email: 'buyer@example.com' },
    seller: { id: 2, name: 'Seller', email: 'seller@example.com' },
    listing: { id: 3, livestock_type: 'Cattle', breed: 'Brahman' },
    quantity: 1,
    total_amount: '100.00',
    status: 'pending',
    created_at: '2026-10-01T00:00:00.000000Z',
    updated_at: '2026-10-01T00:00:00.000000Z',
  };
}

function pageResponse(
  transactions: Transaction[],
  pagination: TransactionsPagination,
): AxiosResponse {
  return {
    data: { success: true, data: { transactions, pagination } },
  } as unknown as AxiosResponse;
}

describe('fetchAllTransactions', () => {
  const getSpy = vi.spyOn(api, 'get');

  afterEach(() => {
    getSpy.mockReset();
  });

  it('walks every page and returns a count equal to the reported total', async () => {
    const firstPage = Array.from({ length: 100 }, (_, index) => makeTransaction(index + 1));
    const secondPage = [makeTransaction(101), makeTransaction(102)];

    getSpy
      .mockResolvedValueOnce(
        pageResponse(firstPage, { current_page: 1, last_page: 2, per_page: 100, total: 102 }),
      )
      .mockResolvedValueOnce(
        pageResponse(secondPage, { current_page: 2, last_page: 2, per_page: 100, total: 102 }),
      );

    const result = await fetchAllTransactions({ status: 'pending' });

    expect(result).toHaveLength(102);
    expect(result[0].id).toBe(1);
    expect(result[101].id).toBe(102);
    expect(getSpy).toHaveBeenCalledTimes(2);
  });

  it('requests pages at the backend per-page cap and forwards the active filters', async () => {
    getSpy.mockResolvedValueOnce(
      pageResponse([], { current_page: 1, last_page: 1, per_page: 100, total: 0 }),
    );

    await fetchAllTransactions({
      search: 'juan',
      status: 'completed',
      date_from: '2026-10-01',
      date_to: '2026-10-12',
    });

    const url = getSpy.mock.calls[0][0] as string;
    expect(url).toContain('per_page=100');
    expect(url).toContain('search=juan');
    expect(url).toContain('status=completed');
    expect(url).toContain('date_from=2026-10-01');
    expect(url).toContain('date_to=2026-10-12');
  });

  it('makes no additional requests when only one page exists', async () => {
    getSpy.mockResolvedValueOnce(
      pageResponse([makeTransaction(1)], { current_page: 1, last_page: 1, per_page: 100, total: 1 }),
    );

    const result = await fetchAllTransactions({});

    expect(result).toHaveLength(1);
    expect(getSpy).toHaveBeenCalledTimes(1);
  });
});
