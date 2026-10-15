import { afterEach, describe, expect, it, vi } from 'vitest';
import type { AxiosResponse } from 'axios';
import api from '../../../../lib/api';
import { fetchActivities, type Activity, type ActivitiesPagination } from './useActivities';

function makeActivity(id: number): Activity {
  return {
    id,
    user: { id: 1, name: 'Admin User', email: 'admin@example.com' },
    action: 'listing_approved',
    description: 'Listing approved',
    metadata: { target_type: 'listing', target_id: 5 },
    created_at: '2026-01-02T03:04:05.000000Z',
    updated_at: '2026-01-02T03:04:05.000000Z',
  };
}

function makeResponse(
  activities: Activity[],
  pagination: ActivitiesPagination,
): AxiosResponse {
  return {
    data: { success: true, data: { activities, pagination } },
  } as AxiosResponse;
}

const pagination: ActivitiesPagination = {
  current_page: 1,
  last_page: 1,
  per_page: 15,
  total: 1,
};

describe('fetchActivities', () => {
  afterEach(() => {
    vi.restoreAllMocks();
  });

  it('returns the activity envelope from the response', async () => {
    const spy = vi
      .spyOn(api, 'get')
      .mockResolvedValueOnce(makeResponse([makeActivity(7)], pagination));

    const result = await fetchActivities({ page: 1, per_page: 15 });

    expect(result.activities).toHaveLength(1);
    expect(result.activities[0].id).toBe(7);
    expect(result.pagination).toEqual(pagination);
    expect(spy).toHaveBeenCalledWith('/admin/activities?page=1&per_page=15');
  });

  it('forwards the page and per_page pagination parameters', async () => {
    const spy = vi.spyOn(api, 'get').mockResolvedValueOnce(makeResponse([], pagination));

    await fetchActivities({ page: 3, per_page: 25 });

    const url = spy.mock.calls[0][0] as string;
    expect(url).toContain('page=3');
    expect(url).toContain('per_page=25');
  });

  it('forwards the search, action, user and date range filters', async () => {
    const spy = vi.spyOn(api, 'get').mockResolvedValueOnce(makeResponse([], pagination));

    await fetchActivities({
      search: 'listing',
      action: 'listing_approved',
      user_id: 12,
      date_from: '2026-01-01',
      date_to: '2026-01-31',
      page: 1,
      per_page: 15,
    });

    const url = spy.mock.calls[0][0] as string;
    expect(url).toContain('search=listing');
    expect(url).toContain('action=listing_approved');
    expect(url).toContain('user_id=12');
    expect(url).toContain('date_from=2026-01-01');
    expect(url).toContain('date_to=2026-01-31');
  });

  it('omits empty filters so the default feed is requested', async () => {
    const spy = vi.spyOn(api, 'get').mockResolvedValueOnce(makeResponse([], pagination));

    await fetchActivities({ page: 1, per_page: 15 });

    const url = spy.mock.calls[0][0] as string;
    expect(url).not.toContain('search=');
    expect(url).not.toContain('action=');
    expect(url).not.toContain('user_id=');
    expect(url).not.toContain('date_from=');
    expect(url).not.toContain('date_to=');
  });
});
