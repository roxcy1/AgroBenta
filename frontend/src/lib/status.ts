/**
 * The one status vocabulary for the Admin Web: the name shown, the tone of its
 * badge, and the colour a chart gives it.
 *
 * Badges, tables and charts all read this map, so "Pending" is the same word
 * and the same colour wherever it appears. Colours are CSS tokens from
 * `index.css`, not hex values, so changing a tone changes every screen.
 *
 * The mobile app uses the same names and tones (see `StatusChip` there).
 */

export type StatusTone = 'neutral' | 'warning' | 'success' | 'info' | 'danger';

interface StatusMeta {
  label: string;
  tone: StatusTone;
  /** A CSS colour for charts. Draft and Inactive differ so a pie can tell them apart. */
  chartColor: string;
}

const STATUS_META: Record<string, StatusMeta> = {
  draft: { label: 'Draft', tone: 'neutral', chartColor: 'var(--color-text-secondary)' },
  inactive: { label: 'Inactive', tone: 'neutral', chartColor: 'var(--color-text-muted)' },
  pending: { label: 'Pending', tone: 'warning', chartColor: 'var(--color-warning)' },
  pending_review: { label: 'Pending Review', tone: 'warning', chartColor: 'var(--color-warning)' },
  submitted: { label: 'Submitted', tone: 'info', chartColor: 'var(--status-info-fg)' },
  sold: { label: 'Sold', tone: 'info', chartColor: 'var(--status-info-fg)' },
  active: { label: 'Active', tone: 'success', chartColor: 'var(--color-primary)' },
  approved: { label: 'Approved', tone: 'success', chartColor: 'var(--color-success)' },
  completed: { label: 'Completed', tone: 'success', chartColor: 'var(--color-success)' },
  cancelled: { label: 'Cancelled', tone: 'danger', chartColor: 'var(--color-danger)' },
  rejected: { label: 'Rejected', tone: 'danger', chartColor: 'var(--color-danger)' },
};

const UNKNOWN: Omit<StatusMeta, 'label'> = {
  tone: 'neutral',
  chartColor: 'var(--color-text-muted)',
};

/** `some_status` -> `Some Status`, for a value this map has not been taught. */
function humanize(status: string): string {
  return status
    .split('_')
    .filter(Boolean)
    .map((word) => word.charAt(0).toUpperCase() + word.slice(1))
    .join(' ');
}

function metaFor(status: string): StatusMeta {
  return STATUS_META[status] ?? { label: humanize(status), ...UNKNOWN };
}

export function statusLabel(status: string): string {
  return metaFor(status).label;
}

export function statusTone(status: string): StatusTone {
  return metaFor(status).tone;
}

export function statusChartColor(status: string): string {
  return metaFor(status).chartColor;
}

/** The CSS classes for a status badge: the shared shape plus the status's tone. */
export function statusBadgeClass(status: string): string {
  return `lv-badge lv-badge--${statusTone(status)}`;
}
