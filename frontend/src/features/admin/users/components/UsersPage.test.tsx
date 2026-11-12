/** @vitest-environment jsdom */
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { act, cleanup, fireEvent, render, screen, waitFor, within } from '@testing-library/react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import type { AxiosResponse } from 'axios';
import { MemoryRouter } from 'react-router-dom';
import api from '../../../../lib/api';
import { ToastProvider } from '../../../../lib/toast/ToastProvider';
import { AuthProvider } from '../../../auth/AuthProvider';
import type { AdminUser } from '../api/useUsers';
import { UsersPage } from './UsersPage';

function makeUser(id: number, overrides: Partial<AdminUser> = {}): AdminUser {
  return {
    id,
    name: `User ${id}`,
    email: `user${id}@example.com`,
    role: 'user',
    seller_capability: 'buyer',
    email_verified_at: null,
    created_at: '2026-10-01T00:00:00.000000Z',
    updated_at: '2026-10-01T00:00:00.000000Z',
    ...overrides,
  };
}

function axiosResponse(data: unknown): AxiosResponse {
  return { data } as AxiosResponse;
}

let users: AdminUser[];
let listRequests: string[];

function responseFor(url: string) {
  const parsed = new URL(url, 'http://localhost');
  const params = parsed.searchParams;

  if (parsed.pathname === '/admin/seller-verifications') {
    return {
      success: true,
      data: {
        verifications: [],
        pagination: { current_page: 1, last_page: 1, per_page: 100, total: 0 },
      },
    };
  }

  if (parsed.pathname === '/admin/users' && params.get('per_page') === '1') {
    const role = params.get('role');
    const capability = params.get('seller_capability');
    const total = capability === 'buyer'
      ? users.filter((user) => user.seller_capability === 'buyer').length
      : capability === 'seller'
        ? users.filter((user) => user.seller_capability === 'seller').length
        : role === 'admin'
          ? users.filter((user) => user.role === 'admin').length
          : users.length;

    return {
      success: true,
      data: { users: users.slice(0, 1), pagination: { current_page: 1, last_page: 1, per_page: 1, total } },
    };
  }

  if (parsed.pathname === '/admin/users') {
    listRequests.push(url);
    let filtered = [...users];
    const search = params.get('search')?.toLowerCase();
    if (search) {
      filtered = filtered.filter((user) =>
        user.name.toLowerCase().includes(search) || user.email.toLowerCase().includes(search),
      );
    }
    const role = params.get('role');
    if (role) filtered = filtered.filter((user) => user.role === role);
    const capability = params.get('seller_capability');
    if (capability) filtered = filtered.filter((user) => user.seller_capability === capability);

    const perPage = Number(params.get('per_page') ?? 15);
    const page = Number(params.get('page') ?? 1);
    const lastPage = Math.max(1, Math.ceil(filtered.length / perPage));
    return {
      success: true,
      data: {
        users: filtered.slice((page - 1) * perPage, page * perPage),
        pagination: {
          current_page: page,
          last_page: lastPage,
          per_page: perPage,
          total: filtered.length,
        },
      },
    };
  }

  const match = parsed.pathname.match(/^\/admin\/users\/(\d+)$/);
  if (match) {
    const user = users.find((candidate) => candidate.id === Number(match[1]));
    return { success: true, data: user ?? null };
  }

  throw new Error(`Unexpected GET ${url}`);
}

function renderUsersPage() {
  const queryClient = new QueryClient({
    defaultOptions: {
      queries: { retry: false, gcTime: 0 },
      mutations: { retry: false },
    },
  });

  render(
    <AuthProvider>
      <QueryClientProvider client={queryClient}>
        <ToastProvider>
          <MemoryRouter>
            <UsersPage />
          </MemoryRouter>
        </ToastProvider>
      </QueryClientProvider>
    </AuthProvider>,
  );
}

async function openActions(user: AdminUser) {
  await screen.findByText(user.name);
  fireEvent.click(screen.getByRole('button', { name: `Actions for ${user.name}` }));
  return screen.findByRole('menu', { name: `Actions for ${user.name}` });
}

describe('UsersPage user actions', () => {
  beforeEach(() => {
    localStorage.removeItem('admin_token');
    users = [makeUser(3, { name: 'Lea Mercado', email: 'lea@example.com' })];
    listRequests = [];
    vi.spyOn(api, 'get').mockImplementation(async (url) =>
      axiosResponse(responseFor(String(url))) as never,
    );
    vi.spyOn(api, 'put').mockRejectedValue(new Error('Unexpected PUT request in test.'));
    vi.spyOn(api, 'delete').mockRejectedValue(new Error('Unexpected DELETE request in test.'));
  });

  afterEach(() => {
    cleanup();
    vi.restoreAllMocks();
  });

  it('keeps the user name details action and offers only Edit and Delete in the menu', async () => {
    renderUsersPage();
    const menu = await openActions(users[0]);

    expect(
      within(menu).getAllByRole('menuitem').map((item) => item.textContent?.trim()),
    ).toEqual(['Edit User', 'Delete User']);

    fireEvent.click(screen.getByRole('button', { name: `Actions for ${users[0].name}` }));
    fireEvent.click(screen.getByText('Lea Mercado'));
    expect(await screen.findByRole('dialog', { name: 'Lea Mercado' })).not.toBeNull();
  });

  it('keeps the actions menu inside a narrow viewport', async () => {
    const originalWidth = window.innerWidth;
    const originalHeight = window.innerHeight;
    Object.defineProperty(window, 'innerWidth', { configurable: true, value: 320 });
    Object.defineProperty(window, 'innerHeight', { configurable: true, value: 480 });
    const rect = (left: number, top: number, width: number, height: number) => ({
      x: left,
      y: top,
      left,
      top,
      right: left + width,
      bottom: top + height,
      width,
      height,
      toJSON: () => ({}),
    }) as DOMRect;
    vi.spyOn(HTMLElement.prototype, 'getBoundingClientRect').mockImplementation(function (this: Element) {
      if (this.classList.contains('users-actions-trigger')) return rect(280, 440, 32, 24);
      if (this.classList.contains('users-actions-menu')) return rect(0, 0, 176, 88);
      return rect(0, 0, 0, 0);
    });

    renderUsersPage();
    await openActions(users[0]);
    const menu = screen.getByRole('menu', { name: `Actions for ${users[0].name}` });

    expect(menu.getAttribute('style')).toContain('left: 136px');
    expect(menu.getAttribute('style')).toContain('top: 348px');
    Object.defineProperty(window, 'innerWidth', { configurable: true, value: originalWidth });
    Object.defineProperty(window, 'innerHeight', { configurable: true, value: originalHeight });
  });

  it('prepopulates and saves the edit dialog, then refreshes the visible table', async () => {
    renderUsersPage();
    await openActions(users[0]);
    fireEvent.click(screen.getByRole('menuitem', { name: 'Edit User' }));
    expect(screen.queryByRole('menu')).toBeNull();

    const dialog = await screen.findByRole('dialog', { name: 'Edit User' });
    const nameInput = within(dialog).getByLabelText('Full Name') as HTMLInputElement;
    const emailInput = within(dialog).getByLabelText('Email Address') as HTMLInputElement;
    expect(nameInput.value).toBe('Lea Mercado');
    expect(emailInput.value).toBe('lea@example.com');

    const updated = makeUser(3, { name: 'Lea Updated', email: 'lea.updated@example.com' });
    vi.spyOn(api, 'put').mockImplementation(async (url, body) => {
      expect(url).toBe('/admin/users/3');
      expect(body).toEqual({ name: 'Lea Updated', email: 'lea.updated@example.com' });
      users = [updated];
      return axiosResponse({ success: true, message: 'User updated.', data: updated }) as never;
    });

    fireEvent.change(nameInput, { target: { value: 'Lea Updated' } });
    fireEvent.change(emailInput, { target: { value: 'lea.updated@example.com' } });
    fireEvent.click(within(dialog).getByRole('button', { name: 'Save Changes' }));

    expect(await screen.findByText('Lea Updated')).not.toBeNull();
    expect(await screen.findByRole('status')).not.toBeNull();
    expect(screen.queryByRole('dialog', { name: 'Edit User' })).toBeNull();
    expect(api.put).toHaveBeenCalledTimes(1);
    await waitFor(() => expect(listRequests.length).toBeGreaterThan(1));
  });

  it('shows local validation errors and does not submit invalid input', async () => {
    renderUsersPage();
    await openActions(users[0]);
    fireEvent.click(screen.getByRole('menuitem', { name: 'Edit User' }));
    const dialog = await screen.findByRole('dialog', { name: 'Edit User' });

    fireEvent.change(within(dialog).getByLabelText('Full Name'), { target: { value: '   ' } });
    fireEvent.change(within(dialog).getByLabelText('Email Address'), { target: { value: 'bad-email' } });
    fireEvent.click(within(dialog).getByRole('button', { name: 'Save Changes' }));

    expect(await within(dialog).findByText('Full name is required.')).not.toBeNull();
    expect(within(dialog).getByText('Enter a valid email address.')).not.toBeNull();
    expect(api.put).not.toHaveBeenCalled();
  });

  it('shows backend uniqueness validation inline', async () => {
    vi.spyOn(api, 'put').mockRejectedValueOnce(Object.assign(new Error('Invalid'), {
      response: {
        status: 422,
        data: {
          message: 'The given data was invalid.',
          errors: { email: ['The email has already been taken.'] },
        },
      },
    }));
    renderUsersPage();
    await openActions(users[0]);
    fireEvent.click(screen.getByRole('menuitem', { name: 'Edit User' }));
    const dialog = await screen.findByRole('dialog', { name: 'Edit User' });
    fireEvent.click(within(dialog).getByRole('button', { name: 'Save Changes' }));

    expect(await within(dialog).findByText('The email has already been taken.')).not.toBeNull();
    expect(screen.queryByRole('dialog', { name: 'Edit User' })).not.toBeNull();
  });

  it('disables the edit form while a save is pending and prevents duplicate requests', async () => {
    let resolveRequest!: (response: AxiosResponse) => void;
    const pendingRequest = new Promise<AxiosResponse>((resolve) => {
      resolveRequest = resolve;
    });
    const put = vi.spyOn(api, 'put').mockReturnValue(pendingRequest as never);

    renderUsersPage();
    await openActions(users[0]);
    fireEvent.click(screen.getByRole('menuitem', { name: 'Edit User' }));
    const dialog = await screen.findByRole('dialog', { name: 'Edit User' });
    const saveButton = within(dialog).getByRole('button', { name: 'Save Changes' });
    fireEvent.click(saveButton);

    await waitFor(() => expect((saveButton as HTMLButtonElement).disabled).toBe(true));
    fireEvent.click(saveButton);
    expect(put).toHaveBeenCalledTimes(1);

    await act(async () => {
      resolveRequest(axiosResponse({ success: true, message: 'User updated.', data: users[0] }));
      await pendingRequest;
    });
  });

  it('cancel closes the edit dialog without saving', async () => {
    renderUsersPage();
    await openActions(users[0]);
    fireEvent.click(screen.getByRole('menuitem', { name: 'Edit User' }));
    const dialog = await screen.findByRole('dialog', { name: 'Edit User' });
    fireEvent.click(within(dialog).getByRole('button', { name: 'Cancel' }));

    expect(screen.queryByRole('dialog', { name: 'Edit User' })).toBeNull();
    expect(api.put).not.toHaveBeenCalled();
  });

  it('confirms deletion with the user identity, preserves cancellation, and refreshes the table', async () => {
    renderUsersPage();
    await openActions(users[0]);
    fireEvent.click(screen.getByRole('menuitem', { name: 'Delete User' }));
    const dialog = await screen.findByRole('alertdialog', { name: 'Delete User' });

    expect(within(dialog).getByText('Lea Mercado')).not.toBeNull();
    expect(within(dialog).getByText('lea@example.com')).not.toBeNull();
    expect(within(dialog).getByText(/transaction history will be retained/i)).not.toBeNull();
    fireEvent.click(within(dialog).getByRole('button', { name: 'Cancel' }));
    expect(screen.queryByRole('alertdialog')).toBeNull();
    expect(api.delete).not.toHaveBeenCalled();

    await openActions(users[0]);
    fireEvent.click(screen.getByRole('menuitem', { name: 'Delete User' }));
    const confirmation = await screen.findByRole('alertdialog', { name: 'Delete User' });
    vi.spyOn(api, 'delete').mockImplementation(async (url) => {
      expect(url).toBe('/admin/users/3');
      const deletedUser = users[0];
      users = [];
      return axiosResponse({ success: true, message: 'User deleted.', data: deletedUser }) as never;
    });

    fireEvent.click(within(confirmation).getByRole('button', { name: 'Confirm Delete' }));
    await waitFor(() => expect(api.delete).toHaveBeenCalledTimes(1));
    expect(await screen.findByText('No users available yet.')).not.toBeNull();
    expect(screen.queryByRole('alertdialog')).toBeNull();
    expect(await screen.findByRole('status')).not.toBeNull();
    const totalUsersCard = screen.getByText('Total Users').closest('.lv-stat-card');
    await waitFor(() => {
      expect(totalUsersCard?.querySelector('.lv-stat-value')?.textContent).toBe('0');
    });
  });

  it('shows a server conflict when deletion fails and keeps the confirmation open', async () => {
    vi.spyOn(api, 'delete').mockRejectedValueOnce(Object.assign(new Error('Conflict'), {
      response: {
        status: 409,
        data: { message: 'The last active administrator cannot be deleted.' },
      },
    }));
    renderUsersPage();
    await openActions(users[0]);
    fireEvent.click(screen.getByRole('menuitem', { name: 'Delete User' }));
    const dialog = await screen.findByRole('alertdialog', { name: 'Delete User' });
    fireEvent.click(within(dialog).getByRole('button', { name: 'Confirm Delete' }));

    expect(await screen.findByRole('alert')).not.toBeNull();
    expect(screen.getByRole('alertdialog', { name: 'Delete User' })).not.toBeNull();
  });

  it('keeps search and pagination behavior available after adding row actions', async () => {
    users = Array.from({ length: 18 }, (_, index) => makeUser(index + 1));
    renderUsersPage();
    expect(await screen.findByText('User 1')).not.toBeNull();

    fireEvent.click(screen.getByRole('button', { name: 'Go to next page' }));
    expect(await screen.findByText('User 16')).not.toBeNull();
    await waitFor(() => expect(listRequests.some((url) => url.includes('page=2'))).toBe(true));

    fireEvent.change(screen.getByRole('textbox', { name: 'Search users by name or email' }), {
      target: { value: 'User 18' },
    });
    fireEvent.click(screen.getByRole('button', { name: 'Search' }));
    expect(await screen.findByText('User 18')).not.toBeNull();
    await waitFor(() => expect(listRequests.some((url) => url.includes('search=User+18'))).toBe(true));
  });

  it('renders the original Users header and keeps rows-per-page pagination available', async () => {
    users = Array.from({ length: 40 }, (_, index) => makeUser(index + 1));
    renderUsersPage();

    expect(await screen.findByRole('heading', { name: 'Users' })).not.toBeNull();
    expect(screen.getByText('Manage platform users')).not.toBeNull();
    expect(screen.queryByText('Livestock Registry')).toBeNull();
    expect(screen.queryByRole('region', { name: 'Livestock seller verification queue' })).toBeNull();
    expect(screen.queryByRole('group', { name: 'Quick user filters' })).toBeNull();
    expect(await screen.findByText('Showing 1–15 of 40 users')).not.toBeNull();

    fireEvent.change(screen.getByLabelText('Filter by role'), { target: { value: 'admin' } });
    expect(screen.getByRole('button', { name: 'Clear filters' })).not.toBeNull();
    fireEvent.click(screen.getByRole('button', { name: 'Clear filters' }));
    expect(screen.queryByRole('button', { name: 'Clear filters' })).toBeNull();

    fireEvent.change(screen.getByRole('combobox', { name: 'Rows per page' }), {
      target: { value: '25' },
    });

    expect(await screen.findByText('Showing 1–25 of 40 users')).not.toBeNull();
    await waitFor(() => {
      expect(listRequests.some((url) => url.includes('per_page=25'))).toBe(true);
    });
  });

  it('renders the original Users columns and identity text without row selectors', async () => {
    users = [makeUser(1, { name: 'Lea Mercado', email: 'lea@example.com' })];
    renderUsersPage();
    await screen.findByText('lea@example.com');

    expect(screen.getAllByRole('columnheader').map((header) => header.textContent?.trim())).toEqual([
      'Name',
      'Email',
      'Role',
      'Seller Capability',
      'Verification Status',
      'Created At',
      'Actions',
    ]);
    expect(screen.getByText('Lea Mercado').closest('td')?.getAttribute('data-label')).toBe('Name');
    expect(screen.getByText('lea@example.com').closest('td')?.getAttribute('data-label')).toBe('Email');
    expect(screen.getByTitle('lea@example.com')).not.toBeNull();
    expect(screen.queryByRole('checkbox')).toBeNull();
  });

  it('keeps the existing verification and seller-capability dropdown filters', async () => {
    users = [
      makeUser(1, { name: 'Lea Seller', seller_capability: 'seller' }),
      makeUser(2, { name: 'Buyer One' }),
    ];
    renderUsersPage();
    await screen.findByText('Lea Seller');

    fireEvent.change(screen.getByLabelText('Filter by verification status'), {
      target: { value: 'pending_review' },
    });
    expect((screen.getByLabelText('Filter by verification status') as HTMLSelectElement).value)
      .toBe('pending_review');
    expect(screen.getByRole('note').textContent).toContain('shown on this page only');

    fireEvent.click(screen.getByRole('button', { name: 'Clear filters' }));
    fireEvent.change(screen.getByLabelText('Filter by seller capability'), {
      target: { value: 'seller' },
    });
    await waitFor(() => {
      expect(listRequests.some((url) => url.includes('seller_capability=seller'))).toBe(true);
    });
    expect(screen.getByText('Lea Seller')).not.toBeNull();
  });
});
