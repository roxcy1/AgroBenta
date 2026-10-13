import { useEffect, useState } from 'react';
import type { SellerVerification } from '../api/useSellerVerifications';
import {
  useApproveVerification,
  useRejectVerification,
} from '../api/useSellerVerifications';
import type { VerificationActionConfig } from './verificationModeration';
import { statusLabel, verificationErrorMessage } from './verificationModeration';

interface VerificationReviewDialogProps {
  verification: SellerVerification;
  action: VerificationActionConfig;
  onClose: () => void;
}

function formatDateTime(value: string | null | undefined): string {
  if (!value) return '—';
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return '—';
  return date.toLocaleString('en-PH', {
    year: 'numeric',
    month: 'short',
    day: 'numeric',
    hour: 'numeric',
    minute: '2-digit',
  });
}

/**
 * The confirmation surface for one verification decision.
 *
 * The applicant's details sit directly above the confirmation so the decision
 * is made against the actual submission rather than against a row in a table.
 * A failure — most usefully a 409 from a record another administrator already
 * decided — is shown in place instead of closing the dialog, so the
 * administrator can see why nothing happened. The mutation hooks invalidate the
 * verification queries regardless, so the list behind the dialog is re-read.
 */
export default function VerificationReviewDialog({
  verification,
  action,
  onClose,
}: VerificationReviewDialogProps) {
  const [adminNote, setAdminNote] = useState('');
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  const approve = useApproveVerification();
  const reject = useRejectVerification();

  const isPending = approve.isPending || reject.isPending;

  useEffect(() => {
    function onKeyDown(event: KeyboardEvent) {
      if (event.key === 'Escape' && !isPending) onClose();
    }
    window.addEventListener('keydown', onKeyDown);
    return () => window.removeEventListener('keydown', onKeyDown);
  }, [onClose, isPending]);

  function handleConfirm() {
    setErrorMessage(null);

    const onError = (error: unknown) => setErrorMessage(verificationErrorMessage(error));
    const onSuccess = () => onClose();
    const adminNoteValue = adminNote.trim() || undefined;

    if (action.action === 'approve') {
      approve.mutate({ id: verification.id, adminNote: adminNoteValue }, { onSuccess, onError });
    } else {
      reject.mutate({ id: verification.id, adminNote: adminNoteValue }, { onSuccess, onError });
    }
  }

  const canConfirm = !isPending && (!action.noteRequired || adminNote.trim() !== '');

  const rows: Array<[string, string]> = [
    ['Applicant', verification.seller?.name ?? '—'],
    ['Email', verification.seller?.email ?? '—'],
    ['Business', verification.business_name],
    ['Location', verification.business_location ?? '—'],
    ['Submitted', formatDateTime(verification.submitted_at)],
  ];

  return (
    <div
      className="lv-action-modal-overlay"
      onClick={() => {
        if (!isPending) onClose();
      }}
    >
      <div
        className="lv-action-modal"
        role="dialog"
        aria-modal="true"
        aria-labelledby="verification-review-title"
        onClick={(event) => event.stopPropagation()}
      >
        <h2 className="lv-action-modal-title" id="verification-review-title">
          {action.confirmTitle}
        </h2>
        <p className="lv-action-modal-desc">{action.confirmMessage}</p>

        <div className="lv-table-container">
          <table className="lv-table">
            <tbody>
              <tr>
                <th>Status</th>
                <td>
                  <span className={`lv-badge lv-badge--${verification.status}`}>
                    {statusLabel(verification.status)}
                  </span>
                </td>
              </tr>
              {rows.map(([label, value]) => (
                <tr key={label}>
                  <th>{label}</th>
                  <td>{value}</td>
                </tr>
              ))}
              {verification.admin_note && (
                <tr>
                  <th>Previous admin note</th>
                  <td>{verification.admin_note}</td>
                </tr>
              )}
            </tbody>
          </table>
        </div>

        <div className="lv-action-modal-field">
          <label className="lv-action-modal-label" htmlFor="verification-admin-note">
            {action.noteRequired ? 'Admin note (required)' : 'Admin note (optional)'}
          </label>
          <textarea
            id="verification-admin-note"
            className="lv-action-modal-textarea"
            value={adminNote}
            maxLength={2000}
            disabled={isPending}
            placeholder="Add a note for this decision..."
            onChange={(event) => setAdminNote(event.target.value)}
          />
        </div>

        {errorMessage && (
          <div className="lv-error">
            <p className="lv-error-text">{errorMessage}</p>
          </div>
        )}

        <div className="lv-action-modal-buttons">
          <button
            type="button"
            className="lv-action-cancel"
            disabled={isPending}
            onClick={onClose}
          >
            Cancel
          </button>
          <button
            type="button"
            className={`lv-action-confirm lv-action-confirm--${action.variant}`}
            disabled={!canConfirm}
            onClick={handleConfirm}
          >
            {isPending ? 'Working…' : action.confirmLabel}
          </button>
        </div>
      </div>
    </div>
  );
}
