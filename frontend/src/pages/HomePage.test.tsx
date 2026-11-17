/** @vitest-environment jsdom */
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { cleanup, render, screen } from '@testing-library/react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import api from '../lib/api';
import HomePage from './HomePage';

const RELEASE = {
  version_name: '1.0.0',
  version_code: 1,
  download_url: 'https://agrobenta.com/storage/releases/agrobenta-1.0.0-1.apk',
  size_bytes: 52_428_800,
  sha256: 'abc',
  notes: null,
  published_at: '2026-11-14T00:00:00+00:00',
};

function mockRelease(data: typeof RELEASE | null) {
  vi.spyOn(api, 'get').mockResolvedValue({ data: { success: true, message: '', data } });
}

function renderHomePage() {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  render(
    <QueryClientProvider client={client}>
      <HomePage />
    </QueryClientProvider>,
  );
}

describe('HomePage', () => {
  beforeEach(() => mockRelease(null));
  afterEach(() => {
    cleanup();
    vi.restoreAllMocks();
  });

  it('introduces AgroBenta with its main sections', () => {
    renderHomePage();

    expect(screen.getByRole('heading', { level: 1 }).textContent)
      .toBe('Buy and sell livestock with people you can trust.');
    expect(screen.getByText('Municipality of Trinidad, Bohol')).not.toBeNull();

    for (const name of ['What AgroBenta does', 'How it works', 'Livestock you can trade', 'Get the AgroBenta mobile app']) {
      expect(screen.getByRole('heading', { level: 2, name })).not.toBeNull();
    }
    for (const type of ['Cattle', 'Carabao', 'Goat', 'Swine', 'Chicken']) {
      expect(screen.getByText(type)).not.toBeNull();
    }
  });

  it('shows the download as a disabled button while no release is published', async () => {
    renderHomePage();

    expect(await screen.findByText(/The mobile app is still in development/)).not.toBeNull();
    const downloads = screen.getAllByRole('button', { name: /Download for Android/ });

    expect(api.get).toHaveBeenCalledWith('/app-release');
    expect(downloads).toHaveLength(2);
    for (const button of downloads) {
      expect((button as HTMLButtonElement).disabled).toBe(true);
      expect(button.textContent).toContain('Coming soon');
      expect(button.closest('a')).toBeNull();
    }
  });

  it('links both download buttons to the published APK', async () => {
    mockRelease(RELEASE);
    renderHomePage();

    const links = await screen.findAllByRole('link', { name: /Download for Android/ });

    expect(links).toHaveLength(2);
    for (const link of links) {
      expect(link.getAttribute('href')).toBe(RELEASE.download_url);
      expect(link.hasAttribute('download')).toBe(true);
      expect(link.textContent).toContain('Version 1.0.0 · 50.0 MB');
    }
    expect(screen.queryByRole('button', { name: /Download for Android/ })).toBeNull();
    expect(screen.queryByText(/still in development/)).toBeNull();
  });

  it('keeps the download disabled when the release request fails', async () => {
    vi.spyOn(api, 'get').mockRejectedValue(new Error('offline'));
    renderHomePage();

    await vi.waitFor(() => expect(api.get).toHaveBeenCalled());
    for (const button of screen.getAllByRole('button', { name: /Download for Android/ })) {
      expect((button as HTMLButtonElement).disabled).toBe(true);
    }
  });

  it('has no link to the admin console', async () => {
    mockRelease(RELEASE);
    renderHomePage();
    await screen.findAllByRole('link', { name: /Download for Android/ });

    const hrefs = screen.getAllByRole('link').map((link) => link.getAttribute('href'));

    // Every link stays on the page (section anchors) or is the app download.
    expect(hrefs.length).toBeGreaterThan(0);
    for (const href of hrefs) {
      expect(href === RELEASE.download_url || /^#/.test(href ?? '')).toBe(true);
    }
    expect(screen.queryByText(/admin login/i)).toBeNull();
    expect(screen.queryByText(/dashboard/i)).toBeNull();
  });
});
