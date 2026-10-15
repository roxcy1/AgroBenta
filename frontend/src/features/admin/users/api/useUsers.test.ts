import { afterEach, describe, expect, it, vi } from 'vitest';
import type { AxiosResponse } from 'axios';
import api from '../../../../lib/api';
import { fetchAdminUser, fetchUsers, type AdminUser, type UsersPagination } from './useUsers';

function makeUser(id: number): AdminUser {
  return {
    id,
    name: `User ${id}`,
    email: `user${id}@example.com`,
    role: 'user',
    seller_capability: 'buyer',
    email_verified_at: null,
    created_at: '2026-10-01T00:00:00.000000Z',
    updated_at: '2026-10-01T00:00:00.000000Z',
  };
}

function usersResponse(users: AdminUser[], pagination: UsersPagination): AxiosResponse {
  return {
    data: { success: true, data: { users, pagination } },
  } as unknown as AxiosResponse;
}

describe('fetchUsers', () => {
  afterEach(() => {
    vi.restoreAllMocks();
  });

  it('returns the users and pagination from the response envelope', async () => {
    vi.spyOn(api, 'get').mockResolvedValueOnce(
      usersResponse([makeUser(1)], { current_page: 1, last_page: 2, per_page: 15, total: 16 }),
    );

    const result = await fetchUsers({ page: 1, per_page: 15 });

    expect(result.users).toHaveLength(1);
    expect(result.users[0].id).toBe(1);
    expect(result.pagination).toEqual({
      current_page: 1,
      last_page: 2,
      per_page: 15,
      total: 16,
    });
  });

  it('forwards the page and per_page pagination parameters', async () => {
    const spy = vi
      .spyOn(api, 'get')
      .mockResolvedValueOnce(
        usersResponse([], { current_page: 2, last_page: 3, per_page: 15, total: 40 }),
      );

    await fetchUsers({ page: 2, per_page: 15 });

    const url = spy.mock.calls[0][0] as string;
    expect(url).toContain('page=2');
    expect(url).toContain('per_page=15');
  });

  it('forwards the search, role and seller capability filters', async () => {
    const spy = vi
      .spyOn(api, 'get')
      .mockResolvedValueOnce(
        usersResponse([], { current_page: 1, last_page: 1, per_page: 15, total: 0 }),
      );

    await fetchUsers({
      search: 'juan',
      role: 'admin',
      seller_capability: 'seller',
      page: 1,
      per_page: 15,
    });

    const url = spy.mock.calls[0][0] as string;
    expect(url).toContain('search=juan');
    expect(url).toContain('role=admin');
    expect(url).toContain('seller_capability=seller');
  });

  it('omits empty filters so only the loaded page is requested', async () => {
    const spy = vi
      .spyOn(api, 'get')
      .mockResolvedValueOnce(
        usersResponse([], { current_page: 1, last_page: 1, per_page: 15, total: 0 }),
      );

    await fetchUsers({ page: 1, per_page: 15 });

    const url = spy.mock.calls[0][0] as string;
    expect(url).not.toContain('search=');
    expect(url).not.toContain('role=');
    expect(url).not.toContain('seller_capability=');
  });
});

describe('fetchAdminUser', () => {
  afterEach(() => {
    vi.restoreAllMocks();
  });

  it('requests the single user by id and returns the record', async () => {
    const spy = vi.spyOn(api, 'get').mockResolvedValueOnce({
      data: { success: true, data: makeUser(7) },
    } as unknown as AxiosResponse);

    const user = await fetchAdminUser(7);

    expect(spy.mock.calls[0][0]).toBe('/admin/users/7');
    expect(user.id).toBe(7);
  });
});
