import { useEffect, useState } from 'react';
import type { AxiosError } from 'axios';
import type { Listing } from '../api/useListings';
import {
  useApproveListing,
  useDeactivateListing,
  useRejectListing,
} from '../api/useListings';
import type { ModerationOption } from './listingModeration';
import { statusLabel } from './listingModeration';

interface ListingReviewDialogProps {
  listing: Listing;
  option: ModerationOption;
  onClose: () => void;
}

/**
 * The confirmation and review surface for one moderation action.
 *
 * Two things are deliberately in one dialog. The confirmation states what will
 * happen — irreversibly, for approval and deactivation, since the lifecycle
 * defines no way back — and the review detail sits directly above it, so the
 * decision is made against the actual listing rather than against a row in a
 * table. A moderator confirming a rejection should be able to see the health
 * records that are missing without reopening anything.
 */
export default function ListingReviewDialog({
  listing,
  option,
  onClose,
}: ListingReviewDialogProps) {
  const [adminNote, setAdminNote] = useState('');
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  const approve = useApproveListing();
  const reject = useRejectListing();
  const deactivate = useDeactivateListing();

  const mutation =
    option.action === 'approve' ? approve : option.action === 'reject' ? reject : deactivate;
  const isPending = mutation.isPending;

  useEffect(() => {
    function onKeyDown(event: KeyboardEvent) {
      if (event.key === 'Escape' && !isPending) onClose();
    }
    window.addEventListener('keydown', onKeyDown);
    return () => window.removeEventListener('keydown', onKeyDown);
  }, [onClose, isPending]);

  function handleConfirm() {
    setErrorMessage(null);

    const onError = (error: unknown) => setErrorMessage(moderationErrorMessage(error));
    const onSuccess = () => onClose();

    // Dispatched per action rather than through a single union of the three
    // mutations: each takes a different argument, and collapsing them into one
    // `mutate` call would make TypeScript infer an intersection of the three
    // signatures — which no call site can satisfy.
    if (option.action === 'approve') {
      approve.mutate(listing.id, { onSuccess, onError });
    } else if (option.action === 'reject') {
      reject.mutate({ id: listing.id, adminNote: adminNote.trim() || undefined }, { onSuccess, onError });
    } else {
      deactivate.mutate(listing.id, { onSuccess, onError });
    }
  }

  const rows: Array<[string, string | null]> = [
    ['Seller', `${listing.seller.name} (${listing.seller.email})`],
    ['Type', listing.livestock_type],
    ['Breed', listing.breed],
    ['Age', listing.age_value !== null ? `${listing.age_value} ${listing.age_unit ?? ''}`.trim() : null],
    ['Gender', listing.gender],
    ['Weight', listing.weight_value !== null ? `${listing.weight_value} ${listing.weight_unit ?? ''}`.trim() : null],
    ['Quantity', String(listing.quantity)],
    ['Asking price', listing.asking_price],
    ['Location', listing.location],
    ['Health status', listing.health_status],
    ['Vaccination', listing.vaccination],
    ['Description', listing.short_description],
    ['Additional notes', listing.additional_notes],
    ['Submitted', new Date(listing.created_at).toLocaleString()],
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
        aria-labelledby="listing-review-title"
        onClick={(event) => event.stopPropagation()}
      >
        <h2 className="lv-action-modal-title" id="listing-review-title">
          {option.confirmTitle}
        </h2>
        <p className="lv-action-modal-desc">{option.confirmMessage}</p>

        <div className="lv-table-container">
          <table className="lv-table">
            <tbody>
              <tr>
                <th>Status</th>
                <td>
                  <span className={`lv-badge lv-badge--${listing.status}`}>
                    {statusLabel(listing.status)}
                  </span>
                </td>
              </tr>
              {rows.map(([label, value]) => (
                <tr key={label}>
                  <th>{label}</th>
                  <td>{value ?? '—'}</td>
                </tr>
              ))}
              {listing.admin_note && (
                <tr>
                  <th>Previous admin note</th>
                  <td>{listing.admin_note}</td>
                </tr>
              )}
            </tbody>
          </table>
        </div>

        {option.action === 'reject' && (
          <div className="lv-action-modal-field">
            <label className="lv-action-modal-label" htmlFor="listing-admin-note">
              Reason (optional)
            </label>
            <textarea
              id="listing-admin-note"
              className="lv-action-modal-textarea"
              value={adminNote}
              maxLength={2000}
              disabled={isPending}
              placeholder="Recorded against the listing for other administrators. Not shown to the seller."
              onChange={(event) => setAdminNote(event.target.value)}
            />
          </div>
        )}

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
            className={`lv-action-confirm lv-action-confirm--${option.variant}`}
            disabled={isPending}
            onClick={handleConfirm}
          >
            {isPending ? 'Working…' : option.confirmLabel}
          </button>
        </div>
      </div>
    </div>
  );
}

/**
 * A moderation failure the moderator can act on.
 *
 * A 409 is the interesting one and gets its own message: the listing was not in
 * a state where this decision applied, which is almost always because another
 * administrator acted on it first. The list query is invalidated by the mutation
 * hook either way, so the row behind the dialog is already being re-read — the
 * message says so rather than leaving the moderator to wonder whether to retry.
 */
function moderationErrorMessage(error: unknown): string {
  const status = (error as AxiosError<{ message?: string }>)?.response?.status;

  switch (status) {
    case 403:
      return 'You do not have permission to moderate listings.';
    case 404:
      return 'This listing no longer exists.';
    case 409:
      return 'This listing has already been decided. The list has been refreshed with its current state.';
    case 422:
      return 'The action was rejected as invalid. Check the details and try again.';
    case 500:
      return 'The server could not complete the action. Please try again.';
    default:
      return 'The action could not be completed. Check your connection and try again.';
  }
}
