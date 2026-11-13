import { useEffect } from 'react';
import type { ReactNode } from 'react';
import { Beef, CalendarDays, ClipboardList, UsersRound } from 'lucide-react';
import type { LucideIcon } from 'lucide-react';
import type { Transaction } from '../api/useTransactions';
import { StatusBadge } from '../../components/StatusBadge';
import { formatDateTime, formatPeso } from '../../../../lib/format';
import { livestockTypeLabel } from '../../livestock/api/useLivestockTypes';
import type { LivestockTypeOption } from '../../livestock/api/useLivestockTypes';
import { AdminDetailModalHeader } from '../../components/AdminDetailModalHeader';

interface TransactionDetailDialogProps {
  transaction: Transaction;
  livestockTypes: LivestockTypeOption[];
  onClose: () => void;
}

function orDash(value: string | number | null | undefined): string {
  if (value === null || value === undefined || value === '') return '\u2014';
  return String(value);
}

/**
 * A contact line for a counterparty.
 *
 * The name and email are rendered together when both are present, but neither is
 * assumed: a transaction whose related user record is incomplete still reads
 * correctly rather than showing an empty parenthesis.
 */
function contactLabel(name?: string | null, email?: string | null): string {
  const parts: string[] = [];
  if (name) parts.push(name);
  if (email) parts.push(`(${email})`);
  return parts.length > 0 ? parts.join(' ') : '\u2014';
}

interface DetailSection {
  title: string;
  Icon: LucideIcon;
  rows: Array<[string, ReactNode]>;
}

export default function TransactionDetailDialog({
  transaction,
  livestockTypes,
  onClose,
}: TransactionDetailDialogProps) {
  useEffect(() => {
    function onKeyDown(event: KeyboardEvent) {
      if (event.key === 'Escape') onClose();
    }
    window.addEventListener('keydown', onKeyDown);
    return () => window.removeEventListener('keydown', onKeyDown);
  }, [onClose]);

  const sections: DetailSection[] = [
    {
      title: 'Summary',
      Icon: ClipboardList,
      rows: [
        ['Transaction ID', `#${transaction.id}`],
        ['Status', <StatusBadge key="status" status={transaction.status} />],
        ['Quantity', orDash(transaction.quantity)],
        ['Total amount', formatPeso(transaction.total_amount)],
      ],
    },
    {
      title: 'Parties',
      Icon: UsersRound,
      rows: [
        ['Buyer', contactLabel(transaction.buyer?.name, transaction.buyer?.email)],
        ['Seller', contactLabel(transaction.seller?.name, transaction.seller?.email)],
      ],
    },
    {
      title: 'Livestock',
      Icon: Beef,
      rows: [
        ['Type', orDash(livestockTypeLabel(transaction.listing?.livestock_type, livestockTypes))],
        ['Breed', orDash(transaction.listing?.breed)],
      ],
    },
    {
      title: 'Record',
      Icon: CalendarDays,
      rows: [
        ['Created', formatDateTime(transaction.created_at)],
        ['Updated', formatDateTime(transaction.updated_at)],
      ],
    },
  ];

  return (
    <div className="lv-action-modal-overlay listing-details-overlay" onClick={onClose}>
      <div
        className="lv-action-modal lv-action-modal--detail lv-action-modal--listing-details"
        role="dialog"
        aria-modal="true"
        aria-labelledby="transaction-detail-title"
        onClick={(event) => event.stopPropagation()}
      >
        <AdminDetailModalHeader
          title={`Transaction #${transaction.id}`}
          subtitle="Buyer and seller details recorded for this transaction."
          titleId="transaction-detail-title"
          closeLabel="Close transaction details"
          onClose={onClose}
        />

        <div className="lv-detail-body">
          <div className="lv-detail-grid">
            {sections.map(({ title, Icon, rows }) => (
              <section className="lv-detail-section" key={title}>
                <h3 className="lv-detail-section-title">
                  <Icon aria-hidden="true" />
                  {title}
                </h3>
                <dl className="lv-detail-list">
                  {rows.map(([label, value]) => (
                    <div className="lv-detail-item" key={label}>
                      <dt className="lv-detail-label">{label}</dt>
                      <dd className="lv-detail-value">{value}</dd>
                    </div>
                  ))}
                </dl>
              </section>
            ))}
          </div>
        </div>

        <footer className="lv-detail-footer listing-details-footer">
          <button type="button" className="listing-details-footer-close" onClick={onClose}>
            Close
          </button>
        </footer>
      </div>
    </div>
  );
}
