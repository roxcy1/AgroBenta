/** @vitest-environment jsdom */
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { cleanup, fireEvent, render, screen } from '@testing-library/react';
import { MemoryRouter, Route, Routes } from 'react-router-dom';
import LoginPage from './LoginPage';

const { loginMock } = vi.hoisted(() => ({ loginMock: vi.fn() }));

vi.mock('../features/auth/AuthProvider', () => ({
  useAuth: () => ({ login: loginMock }),
}));

function renderLoginPage() {
  render(
    <MemoryRouter initialEntries={['/login']}>
      <Routes>
        <Route path="/login" element={<LoginPage />} />
        <Route path="/" element={<p>Admin dashboard</p>} />
      </Routes>
    </MemoryRouter>,
  );
}

describe('LoginPage', () => {
  beforeEach(() => loginMock.mockReset());
  afterEach(cleanup);

  it('renders the responsive split login with AgroBenta branding', () => {
    renderLoginPage();

    expect(screen.getByRole('main').className).toContain('lg:grid-cols-2');
    const logo = screen.getByRole('img', { name: 'AgroBenta' });
    expect(logo.getAttribute('src')).toBe('/images/agrobenta-logo.png');
    expect(screen.getByTestId('login-hero-background').getAttribute('style'))
      .toContain('/images/login-background.webp');
    expect(screen.getByText('Buy. Sell. Grow. Together.')).not.toBeNull();
    expect(screen.getByText('Administrator Access')).not.toBeNull();
    expect(screen.getByRole('heading', { name: 'Administrator Login' })).not.toBeNull();
    expect(screen.getByLabelText('Email Address')).not.toBeNull();
    expect(screen.getByLabelText('Password')).not.toBeNull();
    expect(screen.getByRole('checkbox', { name: 'Remember me' })).not.toBeNull();
  });

  it('toggles password visibility', () => {
    renderLoginPage();
    const password = screen.getByLabelText('Password') as HTMLInputElement;

    expect(password.type).toBe('password');
    fireEvent.click(screen.getByRole('button', { name: 'Show password' }));
    expect(password.type).toBe('text');
    fireEvent.click(screen.getByRole('button', { name: 'Hide password' }));
    expect(password.type).toBe('password');
  });

  it('submits through the existing admin login flow and navigates on success', async () => {
    loginMock.mockResolvedValueOnce(undefined);
    renderLoginPage();

    fireEvent.change(screen.getByLabelText('Email Address'), {
      target: { value: 'admin@example.test' },
    });
    fireEvent.change(screen.getByLabelText('Password'), {
      target: { value: 'correct-password' },
    });
    fireEvent.click(screen.getByRole('button', { name: /log in/i }));

    expect(await screen.findByText('Admin dashboard')).not.toBeNull();
    expect(loginMock).toHaveBeenCalledWith({
      email: 'admin@example.test',
      password: 'correct-password',
    });
  });

  it('keeps existing invalid-credential feedback', async () => {
    loginMock.mockRejectedValueOnce({ response: { status: 401 } });
    renderLoginPage();

    fireEvent.change(screen.getByLabelText('Email Address'), {
      target: { value: 'admin@example.test' },
    });
    fireEvent.change(screen.getByLabelText('Password'), {
      target: { value: 'wrong-password' },
    });
    fireEvent.click(screen.getByRole('button', { name: /log in/i }));

    expect(await screen.findByRole('alert')).not.toBeNull();
    expect(screen.getByText('Invalid email or password.')).not.toBeNull();
  });
});
