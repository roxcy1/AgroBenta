import { ShieldCheck, ShoppingBag, Store, Users } from 'lucide-react';
import type { LucideIcon } from 'lucide-react';
import type { UserStatusCounts } from '../api/useUsers';

export type UserCardKey = 'all' | 'buyer' | 'seller' | 'admin';

interface UserStatsCardsProps {
  counts: UserStatusCounts | undefined;
  activeKey: UserCardKey | '';
  onSelect: (key: UserCardKey) => void;
}

interface StatCard {
  key: UserCardKey;
  countKey: keyof UserStatusCounts;
  label: string;
  variant: string;
  Icon: LucideIcon;
}

const CARDS: readonly StatCard[] = [
  { key: 'all', countKey: 'total', label: 'Total Users', variant: 'total', Icon: Users },
  { key: 'buyer', countKey: 'buyers', label: 'Buyers', variant: 'buyer', Icon: ShoppingBag },
  { key: 'seller', countKey: 'sellers', label: 'Sellers', variant: 'seller', Icon: Store },
  { key: 'admin', countKey: 'admins', label: 'Administrators', variant: 'admin', Icon: ShieldCheck },
];

export default function UserStatsCards({
  counts,
  activeKey,
  onSelect,
}: UserStatsCardsProps) {
  return (
    <div className="lv-stats-grid">
      {CARDS.map(({ key, countKey, label, variant, Icon }) => {
        const isActive = activeKey === key;

        return (
          <button
            key={key}
            type="button"
            className={`lv-stat-card${isActive ? ' lv-stat-card--active' : ''}`}
            aria-pressed={isActive}
            onClick={() => onSelect(key)}
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
