import { beforeEach, describe, expect, it, vi } from 'vitest';
import api from '../../../../lib/api';
import { fetchInquiries, fetchInquiry, updateInquiryStatus } from './useInquiries';

vi.mock('../../../../lib/api', () => ({
  default: {
    get: vi.fn(),
    patch: vi.fn(),
  },
}));

const emptyPage = {
  data: {
    success: true,
    data: {
      inquiries: [],
      pagination: { current_page: 1, last_page: 1, per_page: 15, total: 0 },
    },
  },
};

describe('fetchInquiries', () => {
  beforeEach(() => vi.clearAllMocks());

  it('omits the query string when no filters are given', async () => {
    vi.mocked(api.get).mockResolvedValue(emptyPage);

    await fetchInquiries({});

    expect(vi.mocked(api.get).mock.calls[0][0]).toBe('/admin/inquiries');
  });

  it('encodes search, status, page and per_page into the query string', async () => {
    vi.mocked(api.get).mockResolvedValue(emptyPage);

    await fetchInquiries({ search: 'cow', status: 'open', page: 2, per_page: 15 });

    const url = vi.mocked(api.get).mock.calls[0][0] as string;

    expect(url.startsWith('/admin/inquiries?')).toBe(true);
    expect(url).toContain('search=cow');
    expect(url).toContain('status=open');
    expect(url).toContain('page=2');
    expect(url).toContain('per_page=15');
  });
});

describe('fetchInquiry', () => {
  beforeEach(() => vi.clearAllMocks());

  it('requests the single inquiry by id and unwraps its data', async () => {
    vi.mocked(api.get).mockResolvedValue({ data: { success: true, data: { id: 7 } } });

    const inquiry = await fetchInquiry(7);

    expect(vi.mocked(api.get).mock.calls[0][0]).toBe('/admin/inquiries/7');
    expect(inquiry).toEqual({ id: 7 });
  });
});

describe('updateInquiryStatus', () => {
  beforeEach(() => vi.clearAllMocks());

  it('patches the status sub-resource with only the new status', async () => {
    vi.mocked(api.patch).mockResolvedValue({ data: { success: true, data: { id: 7, status: 'closed' } } });

    const inquiry = await updateInquiryStatus(7, 'closed');

    expect(vi.mocked(api.patch).mock.calls[0][0]).toBe('/admin/inquiries/7/status');
    expect(vi.mocked(api.patch).mock.calls[0][1]).toEqual({ status: 'closed' });
    expect(inquiry).toEqual({ id: 7, status: 'closed' });
  });
});
