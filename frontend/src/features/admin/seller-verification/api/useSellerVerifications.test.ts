import { afterEach, describe, expect, it, vi } from 'vitest';
import type { AxiosResponse } from 'axios';
import api from '../../../../lib/api';
import {
  fetchVerificationCounts,
  fetchVerificationDocument,
} from './useSellerVerifications';

const getSpy = vi.spyOn(api, 'get');

afterEach(() => {
  getSpy.mockReset();
});

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

describe('fetchVerificationDocument', () => {
  it('requests the admin document endpoint as a blob, never as JSON', async () => {
    const blob = new Blob(['bytes'], { type: 'image/png' });
    getSpy.mockResolvedValue({ data: blob } as unknown as AxiosResponse);

    const result = await fetchVerificationDocument(7, 'selfie');

    expect(result).toBe(blob);
    expect(getSpy).toHaveBeenCalledWith(
      '/admin/seller-verifications/7/documents/selfie',
      { responseType: 'blob' },
    );
  });

  it('carries the document type through the path', async () => {
    getSpy.mockResolvedValue({ data: new Blob() } as unknown as AxiosResponse);

    await fetchVerificationDocument(3, 'id_document');

    expect(getSpy).toHaveBeenCalledWith(
      '/admin/seller-verifications/3/documents/id_document',
      { responseType: 'blob' },
    );
  });
});
