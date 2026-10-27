import { useEffect } from 'react';
import type { Transaction } from '../api/useTransactions';

interface TransactionDetailDialogProps {
  transaction: Transaction;
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

/**
 * The ₱ prefix is added to the exact amount string the API returned.
 *
 * The backend already casts the amount to a two-decimal string, so the value is
 * displayed as-is: no parsing, formatting, or re-rounding happens here.
 */
function formatAmount(value: string | null | undefined): string {
  if (value === null || value === undefined || value === '') return '\u2014';
  return `\u20B1${value}`;
}

function formatDateTime(value: string | null | undefined): string {
  if (!value) return '\u2014';
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

function statusLabel(status: string): string {
  return status.charAt(0).toUpperCase() + status.slice(1);
}

export default function TransactionDetailDialog({
  transaction,
  onClose,
}: TransactionDetailDialogProps) {
  useEffect(() => {
    function onKeyDown(event: KeyboardEvent) {
      if (event.key === 'Escape') onClose();
    }
    window.addEventListener('keydown', onKeyDown);
    return () => window.removeEventListener('keydown', onKeyDown);
  }, [onClose]);

  const rows: Array<[string, string]> = [
    ['Buyer', contactLabel(transaction.buyer?.name, transaction.buyer?.email)],
    ['Seller', contactLabel(transaction.seller?.name, transaction.seller?.email)],
    ['Livestock type', orDash(transaction.listing?.livestock_type)],
    ['Breed', orDash(transaction.listing?.breed)],
    ['Quantity', orDash(transaction.quantity)],
    ['Total amount', formatAmount(transaction.total_amount)],
    ['Created', formatDateTime(transaction.created_at)],
    ['Updated', formatDateTime(transaction.updated_at)],
  ];

  return (
    <div className="lv-action-modal-overlay" onClick={onClose}>
      <div
        className="lv-action-modal"
        role="dialog"
        aria-modal="true"
        aria-labelledby="transaction-detail-title"
        onClick={(event) => event.stopPropagation()}
      >
        <h2 className="lv-action-modal-title" id="transaction-detail-title">
          Transaction #{transaction.id}
        </h2>
        <p className="lv-action-modal-desc">
          Buyer and seller details recorded for this transaction.
        </p>

        <div className="lv-table-container">
          <table className="lv-table">
            <tbody>
              <tr>
                <th>Status</th>
                <td>
                  <span className={`lv-badge lv-badge--${transaction.status}`}>
                    {statusLabel(transaction.status)}
                  </span>
                </td>
              </tr>
              <tr>
                <th>Transaction ID</th>
                <td>#{orDash(transaction.id)}</td>
              </tr>
              {rows.map(([label, value]) => (
                <tr key={label}>
                  <th>{label}</th>
                  <td>{value}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>

        <div className="lv-action-modal-buttons">
          <button type="button" className="lv-action-cancel" onClick={onClose}>
            Close
          </button>
        </div>
      </div>
    </div>
  );
}
