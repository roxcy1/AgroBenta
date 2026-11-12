/** @vitest-environment jsdom */
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react';
import { MemoryRouter, Route, Routes } from 'react-router-dom';
import api from '../../../lib/api';
import { AuthProvider } from '../../auth/AuthProvider';
import { Header } from './Header';

function renderHeader() {
  return render(
    <AuthProvider>
      <MemoryRouter initialEntries={['/']}>
        <Header title="Dashboard" profileRole="Administrator" />
        <Routes>
          <Route path="/settings" element={<div>Settings destination</div>} />
          <Route path="/" element={<div>Dashboard destination</div>} />
        </Routes>
      </MemoryRouter>
    </AuthProvider>,
  );
}

describe('Administrator profile dropdown', () => {
  beforeEach(() => {
    localStorage.removeItem('admin_token');
  });

  afterEach(() => {
    cleanup();
    vi.restoreAllMocks();
  });

  it('opens Settings and navigates to the existing Settings route', async () => {
    renderHeader();
    expect(screen.getAllByText('Administrator')).toHaveLength(1);

    fireEvent.click(screen.getByRole('button', { name: 'Open administrator menu' }));
    const settingsLink = screen.getByRole('link', { name: 'Settings' });
    expect(settingsLink.getAttribute('href')).toBe('/settings');

    fireEvent.click(settingsLink);
    expect(await screen.findByText('Settings destination')).not.toBeNull();
    expect(screen.queryByRole('button', { name: 'Sign Out' })).toBeNull();
  });

  it('closes on outside click or Escape and restores focus on Escape', () => {
    renderHeader();
    const trigger = screen.getByRole('button', { name: 'Open administrator menu' });

    fireEvent.click(trigger);
    expect(screen.getByRole('button', { name: 'Sign Out' })).not.toBeNull();
    fireEvent.mouseDown(document.body);
    expect(screen.queryByRole('button', { name: 'Sign Out' })).toBeNull();

    fireEvent.click(trigger);
    fireEvent.keyDown(document, { key: 'Escape' });
    expect(screen.queryByRole('button', { name: 'Sign Out' })).toBeNull();
    expect(document.activeElement).toBe(trigger);
  });

  it('uses the existing logout action and authentication cleanup', async () => {
    const post = vi.spyOn(api, 'post').mockResolvedValue({ data: {} } as never);
    renderHeader();
    localStorage.setItem('admin_token', 'test-token');

    fireEvent.click(screen.getByRole('button', { name: 'Open administrator menu' }));
    fireEvent.click(screen.getByRole('button', { name: 'Sign Out' }));

    await waitFor(() => expect(post).toHaveBeenCalledWith('/admin/auth/logout'));
    expect(localStorage.getItem('admin_token')).toBeNull();
    expect(screen.queryByRole('button', { name: 'Sign Out' })).toBeNull();
  });
});
