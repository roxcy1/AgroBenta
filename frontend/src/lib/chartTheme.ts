/**
 * Chart colours and text sizes for the Admin Web.
 *
 * Shared chart colours come from CSS tokens in `index.css`; livestock species
 * use a fixed semantic palette. Status colours come from `lib/status.ts`.
 * Text sizes live here too, so no chart sets its own.
 */

export const CHART_GRID = 'var(--chart-grid)';
export const CHART_AXIS = 'var(--chart-axis)';
export const CHART_BAR = 'var(--chart-bar)';
export const CHART_BAR_SECONDARY = 'var(--chart-bar-secondary)';
export const CHART_LINE_ACCENT = 'var(--chart-line-accent)';

/** Slice colours for charts that are not about a status (types, actions, roles). */
export const CHART_PIE_COLORS = [
  'var(--chart-pie-1)',
  'var(--chart-pie-2)',
  'var(--chart-pie-3)',
  'var(--chart-pie-4)',
  'var(--chart-pie-5)',
  'var(--chart-pie-6)',
  'var(--chart-pie-7)',
];

/** Stable, semantically matched colors for the dashboard's livestock distribution chart. */
export const CHART_LIVESTOCK_COLORS: Record<string, string> = {
  carabao: '#087C59',
  cattle: '#3B82F6',
  chicken: '#F59E0B',
  goat: '#8B5CF6',
  swine: '#EF4444',
};

export function livestockChartColor(type: string, fallbackIndex: number): string {
  const key = type.trim().toLowerCase();
  return CHART_LIVESTOCK_COLORS[key] ?? CHART_PIE_COLORS[fallbackIndex % CHART_PIE_COLORS.length];
}

/** Axis tick labels, tooltips: the sizes every chart uses. */
export const CHART_TICK = { fontSize: 12 };
export const CHART_TICK_SMALL = { fontSize: 11 };
export const CHART_TOOLTIP_STYLE = { fontSize: 13 };
