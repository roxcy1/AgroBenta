import { CheckCircle, Clock, Package, XCircle } from 'lucide-react';
import type { LucideIcon } from 'lucide-react';
import type { ListingStatusCounts } from '../api/useListings';

interface ListingStatsCardsProps {
  counts: ListingStatusCounts | undefined;
  activeStatus: string;
  onSelect: (status: string) => void;
}

interface StatCard {
  countKey: keyof ListingStatusCounts;
  label: string;
  status: string;
  variant: string;
  Icon: LucideIcon;
}

const CARDS: readonly StatCard[] = [
  { countKey: 'total', label: 'Total Listings', status: '', variant: 'total', Icon: Package },
  { countKey: 'pending', label: 'Pending Listings', status: 'pending', variant: 'pending', Icon: Clock },
  { countKey: 'active', label: 'Active Listings', status: 'active', variant: 'active', Icon: CheckCircle },
  { countKey: 'inactive', label: 'Inactive Listings', status: 'inactive', variant: 'inactive', Icon: XCircle },
];

export default function ListingStatsCards({
  counts,
  activeStatus,
  onSelect,
}: ListingStatsCardsProps) {
  return (
    <div className="lv-stats-grid">
      {CARDS.map(({ countKey, label, status, variant, Icon }) => {
        const isActive = activeStatus === status;

        return (
          <button
            key={countKey}
            type="button"
            className={`lv-stat-card${isActive ? ' lv-stat-card--active' : ''}`}
            aria-pressed={isActive}
            onClick={() => onSelect(status)}
          >
            <span className={`lv-stat-icon lv-stat-icon--${variant}`}>
              <Icon className="lv-stat-icon-svg" aria-hidden="true" />
            </span>
            <span className="lv-stat-info">
              <span className="lv-stat-value">
                {counts ? counts[countKey] : '\u2014'}
              </span>
              <span className="lv-stat-label">{label}</span>
            </span>
          </button>
        );
      })}
    </div>
  );
}
