import { useState } from 'react';
import type { FormEvent } from 'react';
import type { Listing } from '../api/useListings';
import { useReconcileListingInventory } from '../api/useListings';
import { AdminDetailModalHeader } from '../../components/AdminDetailModalHeader';
import './ReconcileInventoryDialog.css';

interface ReconcileInventoryDialogProps {
  listing: Listing;
  onClose: () => void;
  onReconciled: () => void;
}

function parseWholeQuantity(value: string): number | null {
  if (!/^\d+$/.test(value.trim())) return null;
  const parsed = Number(value);
  return Number.isSafeInteger(parsed) ? parsed : null;
}

/** An explicit, evidence-backed resolution of quarantined legacy inventory. */
export default function ReconcileInventoryDialog({
  listing,
  onClose,
  onReconciled,
}: ReconcileInventoryDialogProps) {
  const mutation = useReconcileListingInventory();
  const [physicalQuantity, setPhysicalQuantity] = useState('');
  const [externallySoldQuantity, setExternallySoldQuantity] = useState('');
  const [reason, setReason] = useState('');
  const [evidence, setEvidence] = useState('');
  const [validationMessage, setValidationMessage] = useState<string | null>(null);

  const transactions = listing.unaccounted_inventory_transactions ?? [];
  const pendingQuantity = transactions
    .filter((transaction) => transaction.status === 'pending')
    .reduce((sum, transaction) => sum + transaction.quantity, 0);
  const completedQuantity = transactions
    .filter((transaction) => transaction.status === 'completed')
    .reduce((sum, transaction) => sum + transaction.quantity, 0);

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setValidationMessage(null);

    const physical = parseWholeQuantity(physicalQuantity);
    const external = parseWholeQuantity(externallySoldQuantity);
    if (physical === null || external === null) {
      setValidationMessage('Enter nonnegative whole-number quantities.');
      return;
    }
    if (reason.trim().length < 8) {
      setValidationMessage('Enter a reason of at least 8 characters.');
      return;
    }
    if ((completedQuantity > 0 || external > 0) && evidence.trim().length === 0) {
      setValidationMessage('Add supporting evidence for completed or external sales.');
      return;
    }

    try {
      await mutation.mutateAsync({
        listingId: listing.id,
        input: {
          verified_physical_quantity: physical,
          verified_externally_sold_quantity: external,
          accounted_transaction_ids: transactions.map((transaction) => transaction.id),
          reason: reason.trim(),
          evidence: evidence.trim() || undefined,
        },
      });
      onReconciled();
    } catch (error) {
      setValidationMessage(
        error instanceof Error ? error.message : 'Inventory reconciliation failed. Refresh and try again.',
      );
    }
  }

  return (
    <div className="lv-action-modal-overlay listing-details-overlay" onClick={onClose}>
      <div
        className="lv-action-modal lv-action-modal--detail lv-action-modal--listing-details"
        role="dialog"
        aria-modal="true"
        aria-labelledby="inventory-reconciliation-title"
        onClick={(event) => event.stopPropagation()}
      >
        <AdminDetailModalHeader
          title={`Reconcile listing #${listing.id}`}
          subtitle="Verify physical inventory and account for existing transactions."
          titleId="inventory-reconciliation-title"
          closeLabel="Close inventory reconciliation"
          onClose={onClose}
        />

        <form className="lv-detail-body inventory-reconciliation-form" onSubmit={submit}>
          <section className="lv-detail-section">
            <h3 className="lv-detail-section-title">Unaccounted transactions</h3>
            {transactions.length === 0 ? (
              <p>No pending or completed legacy transactions need allocation.</p>
            ) : (
              <>
                <p>
                  All rows below will be allocated exactly once. Pending animals
                  remain reserved; completed quantities count as platform sales.
                </p>
                <ul>
                  {transactions.map((transaction) => (
                    <li key={transaction.id}>
                      Transaction #{transaction.id}: {transaction.quantity}{' '}
                      {transaction.quantity === 1 ? 'animal' : 'animals'} · {transaction.status}
                    </li>
                  ))}
                </ul>
              </>
            )}
            <p>
              Pending allocation: {pendingQuantity}. Completed platform sales:{' '}
              {completedQuantity}.
            </p>
          </section>

          <div className="lv-action-modal-field">
            <label className="lv-action-modal-label" htmlFor="verified-physical-quantity">
              Physically verified, available quantity
            </label>
            <input
              id="verified-physical-quantity"
              className="inventory-reconciliation-input"
              type="number"
              min="0"
              step="1"
              required
              value={physicalQuantity}
              onChange={(event) => setPhysicalQuantity(event.target.value)}
            />
            <small>Count animals available to new buyers, excluding pending allocations above.</small>
          </div>

          <div className="lv-action-modal-field">
            <label className="lv-action-modal-label" htmlFor="verified-external-quantity">
              Externally sold quantity
            </label>
            <input
              id="verified-external-quantity"
              className="inventory-reconciliation-input"
              type="number"
              min="0"
              step="1"
              required
              value={externallySoldQuantity}
              onChange={(event) => setExternallySoldQuantity(event.target.value)}
            />
            <small>Use only quantities supported by the evidence below.</small>
          </div>

          <div className="lv-action-modal-field">
            <label className="lv-action-modal-label" htmlFor="inventory-reconciliation-reason">
              Reconciliation reason
            </label>
            <textarea
              id="inventory-reconciliation-reason"
              className="lv-action-modal-textarea"
              required
              minLength={8}
              maxLength={1000}
              value={reason}
              onChange={(event) => setReason(event.target.value)}
            />
          </div>

          <div className="lv-action-modal-field">
            <label className="lv-action-modal-label" htmlFor="inventory-reconciliation-evidence">
              Supporting evidence
            </label>
            <textarea
              id="inventory-reconciliation-evidence"
              className="lv-action-modal-textarea"
              maxLength={5000}
              value={evidence}
              onChange={(event) => setEvidence(event.target.value)}
            />
          </div>

          {(validationMessage || mutation.error) && (
            <div role="alert" className="lv-error">
              {validationMessage ?? mutation.error?.message}
            </div>
          )}

          <div className="lv-action-modal-buttons">
            <button type="button" className="lv-action-cancel" onClick={onClose}>
              Cancel
            </button>
            <button type="submit" className="lv-action-confirm lv-action-confirm--approve" disabled={mutation.isPending}>
              {mutation.isPending ? 'Saving…' : 'Save verified inventory'}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}
