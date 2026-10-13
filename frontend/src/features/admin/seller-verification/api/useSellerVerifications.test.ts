import { afterEach, describe, expect, it, vi } from 'vitest';
import type { AxiosResponse } from 'axios';
import api from '../../../../lib/api';
import { fetchVerificationCounts } from './useSellerVerifications';

function countsResponse(total: number): AxiosResponse {
  return {
    data: {
      success: true,
      data: {
        verifications: [],
        pagination: { current_page: 1, last_page: 1, per_page: 1, total },
      },
    },
  } as unknown as AxiosResponse;
}

describe('fetchVerificationCounts', () => {
  const getSpy = vi.spyOn(api, 'get');

  afterEach(() => {
    getSpy.mockReset();
  });

  it('reports the server total for each of the four statuses', async () => {
    getSpy
      .mockResolvedValueOnce(countsResponse(3))
      .mockResolvedValueOnce(countsResponse(5))
      .mockResolvedValueOnce(countsResponse(8))
      .mockResolvedValueOnce(countsResponse(1));

    const counts = await fetchVerificationCounts();

    expect(counts).toEqual({ submitted: 3, pending_review: 5, approved: 8, rejected: 1 });
  });

  it('queries each status separately with per_page=1', async () => {
    getSpy.mockResolvedValue(countsResponse(0));

    await fetchVerificationCounts();

    const urls = getSpy.mock.calls.map((call) => call[0] as string);

    expect(urls).toHaveLength(4);
    for (const status of ['submitted', 'pending_review', 'approved', 'rejected']) {
      expect(
        urls.some((url) => url.includes(`status=${status}`) && url.includes('per_page=1')),
      ).toBe(true);
    }
  });
});
