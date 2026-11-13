/** @vitest-environment jsdom */
import { afterEach, describe, expect, it } from 'vitest';
import { cleanup, render, screen } from '@testing-library/react';
import HomePage from './HomePage';

function renderHomePage() {
  render(<HomePage />);
}

describe('HomePage', () => {
  afterEach(cleanup);

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

  it('shows the mobile download as a disabled button, not a link', () => {
    renderHomePage();

    const downloads = screen.getAllByRole('button', { name: /Download for Android/ });

    expect(downloads).toHaveLength(2);
    for (const button of downloads) {
      expect((button as HTMLButtonElement).disabled).toBe(true);
      expect(button.textContent).toContain('Coming soon');
      expect(button.closest('a')).toBeNull();
    }
    expect(screen.queryByRole('link', { name: /Download/ })?.getAttribute('href')).toBe('#download');
    expect(screen.getByText(/The mobile app is still in development/)).not.toBeNull();
  });

  it('has no link to the admin console', () => {
    renderHomePage();

    const hrefs = screen.getAllByRole('link').map((link) => link.getAttribute('href'));

    // Every link stays on the page: section anchors only.
    expect(hrefs.length).toBeGreaterThan(0);
    for (const href of hrefs) {
      expect(href).toMatch(/^#/);
    }
    expect(screen.queryByText(/admin login/i)).toBeNull();
    expect(screen.queryByText(/dashboard/i)).toBeNull();
  });
});
