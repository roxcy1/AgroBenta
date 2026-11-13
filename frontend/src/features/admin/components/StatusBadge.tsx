import { statusBadgeClass, statusLabel } from '../../../lib/status';

interface StatusBadgeProps {
  status: string;
}

/**
 * The one status badge: the same name and the same restrained colour on every
 * page, for listings, verifications and transactions alike (DESIGN.md §10).
 */
export function StatusBadge({ status }: StatusBadgeProps) {
  return <span className={statusBadgeClass(status)}>{statusLabel(status)}</span>;
}
