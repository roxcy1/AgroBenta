/** @vitest-environment jsdom */
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { AxiosError, AxiosHeaders, type InternalAxiosRequestConfig } from 'axios';
import api from './api';

// The 401 handler signs the administrator out everywhere, but sends the
// browser to /login only from admin pages: the public home page (and the
// login page itself) must stay where they are.

const originalLocation = window.location;
const originalAdapter = api.defaults.adapter;

function failWithStatus(status: number) {
  api.defaults.adapter = async (config: InternalAxiosRequestConfig) => {
    throw new AxiosError('Request failed', String(status), config, undefined, {
      status,
      statusText: '',
      headers: {},
      config: { ...config, headers: new AxiosHeaders() },
      data: {},
    });
  };
}

function visit(pathname: string) {
  Object.defineProperty(window, 'location', {
    configurable: true,
    value: { pathname, href: `http://localhost${pathname}` },
  });
}

async function request() {
  await api.get('/admin/auth/me').catch(() => undefined);
}

describe('api 401 handling', () => {
  beforeEach(() => {
    localStorage.setItem('admin_token', 'expired-token');
  });

  afterEach(() => {
    api.defaults.adapter = originalAdapter;
    Object.defineProperty(window, 'location', { configurable: true, value: originalLocation });
    localStorage.clear();
  });

  it('signs out and stays on the public home page', async () => {
    visit('/');
    failWithStatus(401);

    await request();

    expect(localStorage.getItem('admin_token')).toBeNull();
    expect(window.location.href).toBe('http://localhost/');
  });

  it('signs out and stays on the login page', async () => {
    visit('/login');
    failWithStatus(401);

    await request();

    expect(localStorage.getItem('admin_token')).toBeNull();
    expect(window.location.href).toBe('http://localhost/login');
  });

  it('signs out and sends an admin page to the login page', async () => {
    visit('/dashboard');
    failWithStatus(401);

    await request();

    expect(localStorage.getItem('admin_token')).toBeNull();
    expect(window.location.href).toBe('/login');
  });

  it('leaves the session alone for other errors', async () => {
    visit('/dashboard');
    failWithStatus(500);

    await request();

    expect(localStorage.getItem('admin_token')).toBe('expired-token');
    expect(window.location.href).toBe('http://localhost/dashboard');
  });

  it('still rejects the request so the caller sees the failure', async () => {
    visit('/');
    failWithStatus(401);

    await expect(api.get('/admin/auth/me')).rejects.toBeInstanceOf(AxiosError);
  });
});
