/** @vitest-environment jsdom */
import { afterEach, describe, expect, it, vi } from 'vitest';
import { cleanup, render, screen } from '@testing-library/react';
import { MemoryRouter, Outlet } from 'react-router-dom';
import App from './App';

// Route-level contract for the public home page and the protected admin
// console. The real ProtectedRoute and HomePage run; the admin screens are
// stubbed because this test is about where each URL lands, not their content.
const { authState } = vi.hoisted(() => ({
  authState: { isAuthenticated: false, isLoading: false },
}));

vi.mock('./features/auth/AuthProvider', () => ({
  useAuth: () => authState,
}));
vi.mock('./features/admin/components/AdminLayout', () => ({
  AdminLayout: () => <Outlet />,
}));
vi.mock('./pages/LoginPage', () => ({ default: () => <p>Login page</p> }));
vi.mock('./pages/AdminHomePage', () => ({ default: () => <p>Dashboard page</p> }));
vi.mock('./pages/UsersPage', () => ({ default: () => <p>Users page</p> }));
vi.mock('./pages/SettingsPage', () => ({ default: () => <p>Settings page</p> }));
// The home page's download button reads the latest release; no request here.
vi.mock('./features/appRelease/useAppRelease', () => ({
  useAppRelease: () => ({ data: null }),
  formatReleaseSize: () => '',
}));

function renderAt(path: string) {
  render(
    <MemoryRouter initialEntries={[path]}>
      <App />
    </MemoryRouter>,
  );
}

const HOME_HEADING = 'Buy and sell livestock with people you can trust.';

describe('App routes', () => {
  afterEach(() => {
    cleanup();
    authState.isAuthenticated = false;
    authState.isLoading = false;
  });

  it('serves the public home page at / to a signed-out visitor', () => {
    renderAt('/');

    expect(screen.getByRole('heading', { level: 1 }).textContent).toBe(HOME_HEADING);
    expect(screen.queryByText('Login page')).toBeNull();
  });

  it('keeps a signed-in administrator on the home page at /', () => {
    authState.isAuthenticated = true;
    renderAt('/');

    expect(screen.getByRole('heading', { level: 1 }).textContent).toBe(HOME_HEADING);
    expect(screen.queryByText('Dashboard page')).toBeNull();
  });

  it('sends a signed-out visitor from /dashboard to the login page', () => {
    renderAt('/dashboard');

    expect(screen.getByText('Login page')).not.toBeNull();
    expect(screen.queryByText('Dashboard page')).toBeNull();
  });

  it('protects the other admin pages the same way', () => {
    renderAt('/users');

    expect(screen.getByText('Login page')).not.toBeNull();
    expect(screen.queryByText('Users page')).toBeNull();
  });

  it('shows the dashboard at /dashboard to a signed-in administrator', () => {
    authState.isAuthenticated = true;
    renderAt('/dashboard');

    expect(screen.getByText('Dashboard page')).not.toBeNull();
  });

  it('waits for the session check before deciding on /dashboard', () => {
    authState.isLoading = true;
    renderAt('/dashboard');

    expect(screen.queryByText('Login page')).toBeNull();
    expect(screen.queryByText('Dashboard page')).toBeNull();
  });

  it('keeps the old /admin/settings link working for administrators', () => {
    authState.isAuthenticated = true;
    renderAt('/admin/settings');

    expect(screen.getByText('Settings page')).not.toBeNull();
  });

  it('sends unknown addresses to the home page', () => {
    renderAt('/no-such-page');

    expect(screen.getByRole('heading', { level: 1 }).textContent).toBe(HOME_HEADING);
  });
});
