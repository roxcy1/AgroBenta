/** @vitest-environment jsdom */
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { cleanup, fireEvent, render, screen, waitFor, within } from '@testing-library/react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import type { AxiosResponse } from 'axios';
import api from '../../../../lib/api';
import { ToastProvider } from '../../../../lib/toast/ToastProvider';
import { AuthProvider } from '../../../auth/AuthProvider';
import SettingsPage from '../../../../pages/SettingsPage';

function axiosResponse(data: unknown): AxiosResponse {
  return { data } as AxiosResponse;
}

const settingsData = {
  system: [
    {
      key: 'system.name',
      value: 'AgroBenta',
      group: 'system',
      label: 'System Name',
      description: 'The display name of the platform.',
    },
    {
      key: 'system.description',
      value: 'A livestock trading platform connecting buyers and sellers.',
      group: 'system',
      label: 'System Description',
      description: 'A brief description of the platform.',
    },
  ],
  admin_contact: [
    {
      key: 'admin_contact.name',
      value: 'Administrator',
      group: 'admin_contact',
      label: 'Contact Name',
      description: 'Name displayed as the platform contact.',
    },
    {
      key: 'admin_contact.email',
      value: 'admin@agrobenta.example.com',
      group: 'admin_contact',
      label: 'Contact Email',
      description: 'Email address for platform inquiries.',
    },
    {
      key: 'admin_contact.phone',
      value: '',
      group: 'admin_contact',
      label: 'Contact Phone',
      description: 'Phone number for platform inquiries.',
    },
  ],
} as const;

function renderSettingsPage() {
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
          <SettingsPage />
        </ToastProvider>
      </QueryClientProvider>
    </AuthProvider>,
  );
}

describe('SettingsPage', () => {
  beforeEach(() => {
    localStorage.removeItem('admin_token');
    vi.spyOn(api, 'get').mockResolvedValue(
      axiosResponse({ success: true, data: settingsData }) as never,
    );
    vi.spyOn(api, 'put').mockRejectedValue(new Error('Unexpected settings update.'));
  });

  afterEach(() => {
    cleanup();
    vi.restoreAllMocks();
  });

  it('shows the existing settings fields and restores unsaved edits without sending a request', async () => {
    renderSettingsPage();

    expect(await screen.findByRole('heading', { name: 'Settings' })).not.toBeNull();
    expect(screen.getByText('Manage platform settings'))
      .not.toBeNull();
    expect(await screen.findByRole('heading', { name: 'General Settings' })).not.toBeNull();
    expect(screen.getByRole('heading', { name: 'Administrator Contact' })).not.toBeNull();
    expect(screen.getByLabelText('System Name')).not.toBeNull();
    expect(screen.getByLabelText('System Description')).not.toBeNull();
    expect(screen.getByLabelText('Contact Name')).not.toBeNull();
    expect(screen.getByLabelText('Contact Email')).not.toBeNull();
    const phoneInput = screen.getByLabelText('Contact Phone') as HTMLInputElement;
    expect(phoneInput.value).toBe('');
    expect(phoneInput.placeholder).toBe('Enter contact phone number');
    expect(screen.getByLabelText('Maximum Photos per Listing')).not.toBeNull();
    expect(screen.getByLabelText('Verification Guidance')).not.toBeNull();

    const systemName = screen.getByLabelText('System Name') as HTMLInputElement;
    fireEvent.change(systemName, { target: { value: 'AgroBenta Test' } });
    expect(screen.getByText('Unsaved changes')).not.toBeNull();

    fireEvent.click(screen.getByRole('button', { name: 'Reset Changes' }));

    expect(systemName.value).toBe('AgroBenta');
    expect(screen.queryByText('Unsaved changes')).toBeNull();
    expect(api.put).not.toHaveBeenCalled();
  });

  it('validates required fields and saves only changed values through the existing confirmation flow', async () => {
    renderSettingsPage();
    const systemName = await screen.findByLabelText('System Name') as HTMLInputElement;
    const saveButton = screen.getByRole('button', { name: 'Save Changes' });

    fireEvent.change(systemName, { target: { value: '' } });
    fireEvent.click(saveButton);
    expect(await screen.findByText('System Name is required.')).not.toBeNull();
    expect(screen.queryByRole('dialog', { name: 'Save changes?' })).toBeNull();
    expect(api.put).not.toHaveBeenCalled();

    const updatedValue = 'AgroBenta Marketplace';
    const updatedSettings = {
      ...settingsData,
      system: settingsData.system.map((setting) =>
        setting.key === 'system.name' ? { ...setting, value: updatedValue } : setting,
      ),
    };
    vi.spyOn(api, 'put').mockImplementation(async (url, payload) => {
      expect(url).toBe('/admin/settings');
      expect(payload).toEqual({ 'system.name': updatedValue });
      return axiosResponse({
        success: true,
        message: 'Settings updated.',
        data: updatedSettings,
        updated: ['system.name'],
        rejected: [],
      }) as never;
    });

    fireEvent.change(systemName, { target: { value: updatedValue } });
    fireEvent.click(saveButton);
    const confirmation = await screen.findByRole('dialog', { name: 'Save changes?' });
    fireEvent.click(within(confirmation).getByRole('button', { name: 'Save' }));

    expect(await screen.findByRole('status')).not.toBeNull();
    await waitFor(() => expect(systemName.value).toBe(updatedValue));
  });
});
