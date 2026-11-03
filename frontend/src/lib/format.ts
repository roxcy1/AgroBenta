/**
 * The one place the Admin Web formats money, dates and counts.
 *
 * Every page used to carry its own copy, and the copies disagreed (`₱0` or
 * `₱0.00`, a date with or without a year, a raw amount with no thousands
 * separator). Using these everywhere is what makes `₱42,500.00` and
 * `Nov 2, 2026` read the same on every screen.
 */

const LOCALE = 'en-PH';
const NO_VALUE = '—';

/**
 * A peso amount, e.g. `₱42,500.00`.
 *
 * A decimal string from the API (`"42500.00"`) is grouped digit by digit and
 * never parsed, so the exact amount the server sent is the amount shown — no
 * float rounding on a large value. Numbers (report totals) are formatted with
 * two decimals. Anything missing or not a number is a dash, not `₱0`, because
 * a zero is a real amount and a missing one is not.
 */
export function formatPeso(value: string | number | null | undefined): string {
  if (value === null || value === undefined || value === '') return NO_VALUE;

  if (typeof value === 'string') {
    const decimal = /^(-?)(\d+)(?:\.(\d{0,2}))?$/.exec(value.trim());
    if (decimal) {
      const [, sign, whole, fraction = ''] = decimal;
      const grouped = whole.replace(/\B(?=(\d{3})+(?!\d))/g, ',');
      return `${sign}₱${grouped}.${fraction.padEnd(2, '0')}`;
    }
  }

  const amount = typeof value === 'number' ? value : Number.parseFloat(value);
  if (!Number.isFinite(amount)) return NO_VALUE;

  return `₱${amount.toLocaleString(LOCALE, {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  })}`;
}

function parseDate(value: string | null | undefined): Date | null {
  if (!value) return null;
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? null : date;
}

/** A calendar date, e.g. `Nov 2, 2026`. A missing or invalid value is a dash. */
export function formatDate(value: string | null | undefined): string {
  const date = parseDate(value);
  if (!date) return NO_VALUE;

  return date.toLocaleDateString(LOCALE, {
    year: 'numeric',
    month: 'short',
    day: 'numeric',
  });
}

/** A date with its time, e.g. `Nov 2, 2026, 3:59 PM`, for detail views. */
export function formatDateTime(value: string | null | undefined): string {
  const date = parseDate(value);
  if (!date) return NO_VALUE;

  return date.toLocaleString(LOCALE, {
    year: 'numeric',
    month: 'short',
    day: 'numeric',
    hour: 'numeric',
    minute: '2-digit',
  });
}

/** A count with thousands separators, e.g. `1,250`. */
export function formatNumber(value: number): string {
  return value.toLocaleString(LOCALE);
}
