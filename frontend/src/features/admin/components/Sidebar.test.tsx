/** @vitest-environment jsdom */
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { cleanup, render, screen } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import api from '../../../lib/api';
import { AuthProvider } from '../../auth/AuthProvider';
import { Sidebar } from './Sidebar';

describe('Sidebar navigation', () => {
  beforeEach(() => {
    localStorage.removeItem('admin_token');
    vi.spyOn(api, 'get').mockResolvedValue({
      data: {
        success: true,
        data: {
          verifications: [],
          pagination: { current_page: 1, last_page: 1, per_page: 1, total: 3 },
        },
      },
    } as never);
  });

  afterEach(() => {
    cleanup();
    vi.restoreAllMocks();
  });

  it('groups the existing routes and highlights the current page', async () => {
    const queryClient = new QueryClient({ defaultOptions: { queries: { retry: false } } });
    render(
      <QueryClientProvider client={queryClient}>
        <AuthProvider>
          <MemoryRouter initialEntries={['/users']}>
            <Sidebar />
          </MemoryRouter>
        </AuthProvider>
      </QueryClientProvider>,
    );

    const expectedRoutes = [
      ['Dashboard', '/dashboard'],
      ['Livestock', '/livestock'],
      ['Users', '/users'],
      ['Seller Verification', '/seller-verification'],
      ['Transactions', '/transactions'],
      ['Activities', '/activities'],
      ['Reports', '/reports'],
      ['Settings', '/settings'],
    ];

    for (const [label, route] of expectedRoutes) {
      expect(screen.getByRole('link', { name: new RegExp(`^${label}`) }).getAttribute('href')).toBe(route);
    }

    expect(screen.getByRole('link', { name: 'Users' }).className).toContain('sidebar-nav-item--active');
    expect(screen.getByText('Overview')).not.toBeNull();
    expect(screen.getByText('Marketplace')).not.toBeNull();
    expect(screen.getByText('Management')).not.toBeNull();
    expect(screen.getByText('System')).not.toBeNull();
    expect(await screen.findByText('3')).not.toBeNull();
    expect(screen.queryByRole('button', { name: /sign out/i })).toBeNull();
  });
});
