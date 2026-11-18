/** @vitest-environment jsdom */
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { cleanup, fireEvent, render, screen, waitFor, within } from '@testing-library/react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import type { AxiosResponse } from 'axios';
import api from '../../../../lib/api';
import { ToastProvider } from '../../../../lib/toast/ToastProvider';
import type { AdminUserReport } from '../api/useUserReports';
import UserReportsTab from './UserReportsTab';

function makeReport(overrides: Partial<AdminUserReport> = {}): AdminUserReport {
  return {
    id: 7,
    reason: 'scam_fraud',
    reason_label: 'Scam/Fraud',
    description: 'Asked for payment outside the platform.',
    status: 'pending',
    status_label: 'Pending',
    reporter: { id: 11, name: 'Reporter One' },
    reported_user: {
      id: 22,
      name: 'Reported User',
      status: 'active',
      pending_transactions_count: 0,
    },
    has_evidence: false,
    reviewer: null,
    reviewed_at: null,
    admin_note: null,
    created_at: '2026-11-01T00:00:00.000000Z',
    ...overrides,
  };
}

function axiosResponse(data: unknown): AxiosResponse {
  return { data } as AxiosResponse;
}

function reportsResponse(reports: AdminUserReport[]): AxiosResponse {
  return axiosResponse({
    success: true,
    data: {
      reports,
      pagination: {
        current_page: 1,
        last_page: 1,
        per_page: 15,
        total: reports.length,
      },
    },
  });
}

function renderTab() {
  const queryClient = new QueryClient({
    defaultOptions: {
      queries: { retry: false, gcTime: 0 },
      mutations: { retry: false },
    },
  });

  render(
    <QueryClientProvider client={queryClient}>
      <ToastProvider>
        <UserReportsTab />
      </ToastProvider>
    </QueryClientProvider>,
  );
}

describe('UserReportsTab', () => {
  beforeEach(() => {
    localStorage.removeItem('admin_token');
  });

  afterEach(() => {
    cleanup();
    vi.restoreAllMocks();
  });

  it('renders report rows, filters by status, and opens the review modal', async () => {
    const report = makeReport();
    const get = vi.spyOn(api, 'get').mockImplementation(async (url) => {
      if (String(url).startsWith('/admin/user-reports/7')) {
        return axiosResponse({ success: true, data: report }) as never;
      }
      return reportsResponse([report]) as never;
    });

    renderTab();
    expect(await screen.findByText('Reporter One')).not.toBeNull();
    expect(screen.getAllByText('Reported User').length).toBeGreaterThan(0);
    expect(screen.getByText('Scam/Fraud')).not.toBeNull();

    fireEvent.change(screen.getByLabelText('Filter reports by status'), {
      target: { value: 'pending' },
    });
    await waitFor(() => {
      expect(get.mock.calls.some(([url]) => String(url).includes('status=pending'))).toBe(true);
    });

    fireEvent.click(screen.getByRole('button', { name: 'Review report 7' }));
    const dialog = await screen.findByRole('dialog', { name: 'Report #7' });
    expect(within(dialog).getByText('Asked for payment outside the platform.')).not.toBeNull();
    expect(within(dialog).getByText('No screenshot was provided.')).not.toBeNull();
    expect(within(dialog).getByRole('button', { name: 'Dismiss Report' })).not.toBeNull();
    expect(within(dialog).getByRole('button', { name: 'Deactivate Account' })).not.toBeNull();
  });

  it('dismisses a report with an optional note', async () => {
    const report = makeReport();
    vi.spyOn(api, 'get').mockImplementation(async (url) => {
      if (String(url).startsWith('/admin/user-reports/7')) {
        return axiosResponse({ success: true, data: report }) as never;
      }
      return reportsResponse([report]) as never;
    });
    const post = vi.spyOn(api, 'post').mockResolvedValue(
      axiosResponse({
        success: true,
        message: 'Report dismissed.',
        data: { ...report, status: 'dismissed', status_label: 'Dismissed' },
      }) as never,
    );

    renderTab();
    fireEvent.click(await screen.findByRole('button', { name: 'Review report 7' }));
    const dialog = await screen.findByRole('dialog', { name: 'Report #7' });
    fireEvent.click(within(dialog).getByRole('button', { name: 'Dismiss Report' }));
    fireEvent.change(within(dialog).getByLabelText('Administrative note (optional)'), {
      target: { value: 'Evidence was inconclusive.' },
    });
    fireEvent.click(within(dialog).getByRole('button', { name: 'Confirm Dismissal' }));

    await waitFor(() => expect(post).toHaveBeenCalledTimes(1));
    expect(post.mock.calls[0][0]).toBe('/admin/user-reports/7/dismiss');
    expect(post.mock.calls[0][1]).toEqual({ admin_note: 'Evidence was inconclusive.' });
    await waitFor(() => expect(screen.queryByRole('dialog', { name: 'Report #7' })).toBeNull());
  });

  it('requires a reason before deactivating from a report', async () => {
    const report = makeReport({
      reported_user: {
        id: 22,
        name: 'Reported User',
        status: 'active',
        pending_transactions_count: 1,
      },
    });
    vi.spyOn(api, 'get').mockImplementation(async (url) => {
      if (String(url).startsWith('/admin/user-reports/7')) {
        return axiosResponse({ success: true, data: report }) as never;
      }
      return reportsResponse([report]) as never;
    });
    const post = vi.spyOn(api, 'post').mockResolvedValue(
      axiosResponse({
        success: true,
        message: 'Report actioned and account deactivated.',
        data: { ...report, status: 'actioned', status_label: 'Actioned' },
      }) as never,
    );

    renderTab();
    fireEvent.click(await screen.findByRole('button', { name: 'Review report 7' }));
    const dialog = await screen.findByRole('dialog', { name: 'Report #7' });
    fireEvent.click(within(dialog).getByRole('button', { name: 'Deactivate Account' }));
    expect(within(dialog).getByText(/pending\s+transaction/)).not.toBeNull();
    const confirm = within(dialog).getByRole('button', { name: 'Confirm Deactivation' });
    expect((confirm as HTMLButtonElement).disabled).toBe(true);

    fireEvent.change(within(dialog).getByLabelText('Administrative reason'), {
      target: { value: 'Scam confirmed by the screenshot.' },
    });
    fireEvent.click(confirm);

    await waitFor(() => expect(post).toHaveBeenCalledTimes(1));
    expect(post.mock.calls[0][0]).toBe('/admin/user-reports/7/deactivate');
    expect(post.mock.calls[0][1]).toEqual({ reason: 'Scam confirmed by the screenshot.' });
  });
});
