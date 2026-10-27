import { ArrowLeftRight, CheckCircle, Clock, XCircle } from 'lucide-react';
import type { LucideIcon } from 'lucide-react';
import type { TransactionStatusCounts } from '../api/useTransactions';

interface TransactionStatsCardsProps {
  counts: TransactionStatusCounts | undefined;
  activeStatus: string;
  onSelect: (status: string) => void;
}

interface StatCard {
  countKey: keyof TransactionStatusCounts;
  label: string;
  status: string;
  variant: string;
  Icon: LucideIcon;
}

const CARDS: readonly StatCard[] = [
  { countKey: 'total', label: 'Total Transactions', status: '', variant: 'total', Icon: ArrowLeftRight },
  { countKey: 'pending', label: 'Pending Transactions', status: 'pending', variant: 'pending', Icon: Clock },
  { countKey: 'completed', label: 'Completed Transactions', status: 'completed', variant: 'completed', Icon: CheckCircle },
  { countKey: 'cancelled', label: 'Cancelled Transactions', status: 'cancelled', variant: 'cancelled', Icon: XCircle },
];

export default function TransactionStatsCards({
  counts,
  activeStatus,
  onSelect,
}: TransactionStatsCardsProps) {
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
              <Icon className="lv-stat-icon-svg" />
            </span>
            <span className="lv-stat-info">
              <span className="lv-stat-value">
                {counts ? counts[countKey] : '—'}
              </span>
              <span className="lv-stat-label">{label}</span>
            </span>
          </button>
        );
      })}
    </div>
  );
}
