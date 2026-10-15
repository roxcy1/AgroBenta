export interface ActivityChange {
  field: string;
  label: string;
  from: string;
  to: string;
}

export interface ActivityContextEntry {
  field: string;
  label: string;
  value: string;
}

export interface ActivityFilterState {
  search?: string;
  action?: string;
  user_id?: number;
  date_from?: string;
  date_to?: string;
}

// Mirrors the backend `ActivityAction` enum so the action filter offers a
// known vocabulary instead of free text. Kept in sync with
// backend/app/Enums/ActivityAction.php, matching how the users and
// transactions pages expose their own backend vocabularies as filter options.
export const ACTIVITY_ACTION_OPTIONS = [
  { value: '', label: 'All Actions' },
  { value: 'admin_logged_in', label: 'Administrator signed in' },
  { value: 'user_logged_in', label: 'User signed in' },
  { value: 'listing_created', label: 'Listing created' },
  { value: 'listing_submitted', label: 'Listing submitted' },
  { value: 'listing_updated', label: 'Listing updated' },
  { value: 'listing_deleted', label: 'Listing deleted' },
  { value: 'listing_approved', label: 'Listing approved' },
  { value: 'listing_rejected', label: 'Listing rejected' },
  { value: 'listing_deactivated', label: 'Listing deactivated' },
  { value: 'listing_photo_removed', label: 'Listing photo removed' },
  { value: 'seller_verification_submitted', label: 'Seller verification submitted' },
  { value: 'seller_verification_approved', label: 'Seller verification approved' },
  { value: 'seller_verification_rejected', label: 'Seller verification rejected' },
  { value: 'transaction_created', label: 'Transaction created' },
  { value: 'transaction_cancelled', label: 'Transaction cancelled' },
  { value: 'settings_updated', label: 'Settings updated' },
] as const;

const SENSITIVE_KEY = /pass|secret|token|credential|api[_-]?key/i;

function asRecord(value: unknown): Record<string, unknown> | null {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) return null;
  return value as Record<string, unknown>;
}

function hasKey(record: Record<string, unknown>, key: string): boolean {
  return Object.prototype.hasOwnProperty.call(record, key);
}

export function humanizeLabel(value: string): string {
  const words = value
    .replace(/[_-]+/g, ' ')
    .trim()
    .split(/\s+/)
    .filter(Boolean);

  if (words.length === 0) return '\u2014';

  return words
    .map((word) => word.charAt(0).toUpperCase() + word.slice(1))
    .join(' ');
}

export function activityActionLabel(action: string): string {
  if (!action || !action.trim()) return 'Unknown action';
  return humanizeLabel(action);
}

export function activityActorLabel(user: { name: string } | null | undefined): string {
  if (user && user.name && user.name.trim()) return user.name;
  return 'System';
}

export function formatMetadataValue(value: unknown): string {
  if (value === null || value === undefined || value === '') return '\u2014';
  if (Array.isArray(value)) {
    return value.length === 0 ? '\u2014' : value.map((item) => formatMetadataValue(item)).join(', ');
  }
  if (typeof value === 'object') {
    try {
      return JSON.stringify(value);
    } catch {
      return '\u2014';
    }
  }
  return String(value);
}

export function activityTargetLabel(metadata: Record<string, unknown> | null | undefined): string {
  if (!metadata) return '\u2014';

  const type = metadata.target_type;
  const id = metadata.target_id;
  const typeLabel = typeof type === 'string' && type.trim() ? humanizeLabel(type) : null;
  const hasId = typeof id === 'number' || (typeof id === 'string' && id.trim() !== '');

  if (!typeLabel && !hasId) return '\u2014';
  if (typeLabel && hasId) return `${typeLabel} #${id}`;
  if (typeLabel) return typeLabel;
  return `#${id}`;
}

export function activityChanges(
  metadata: Record<string, unknown> | null | undefined,
): ActivityChange[] {
  const changes = asRecord(metadata?.changes);
  if (!changes) return [];

  return Object.entries(changes).flatMap(([field, raw]) => {
    const entry = asRecord(raw);
    if (!entry || !hasKey(entry, 'from') || !hasKey(entry, 'to')) return [];

    return [
      {
        field,
        label: humanizeLabel(field),
        from: formatMetadataValue(entry.from),
        to: formatMetadataValue(entry.to),
      },
    ];
  });
}

export function activityContextEntries(
  metadata: Record<string, unknown> | null | undefined,
): ActivityContextEntry[] {
  const context = asRecord(metadata?.context);
  if (!context) return [];

  return Object.entries(context)
    .filter(([field]) => !SENSITIVE_KEY.test(field))
    .map(([field, value]) => ({
      field,
      label: humanizeLabel(field),
      value: formatMetadataValue(value),
    }));
}

export function hasActiveActivityFilters(filters: {
  search?: string;
  action?: string;
  user_id?: number;
  date_from?: string;
  date_to?: string;
}): boolean {
  return Boolean(
    filters.search || filters.action || filters.user_id || filters.date_from || filters.date_to,
  );
}

export function emptyActivitiesMessage(hasFilters: boolean): string {
  return hasFilters
    ? 'No activities match the current filters.'
    : 'No activities have been recorded yet.';
}

export function formatActivityTimestamp(value: string): string {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return '\u2014';

  return date.toLocaleString('en-PH', {
    year: 'numeric',
    month: 'short',
    day: 'numeric',
    hour: 'numeric',
    minute: '2-digit',
  });
}

export function activityTimestampTitle(value: string): string {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return value;

  return date.toLocaleString('en-PH', {
    year: 'numeric',
    month: 'long',
    day: 'numeric',
    hour: 'numeric',
    minute: '2-digit',
    second: '2-digit',
  });
}
