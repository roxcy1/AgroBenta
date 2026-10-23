import { useEffect, useState } from 'react';
import type { ReactNode } from 'react';
import { useDeleteInquiry, useInquiry, useUpdateInquiryStatus } from '../api/useInquiries';
import {
  INQUIRY_STATUSES,
  contactMethodLabel,
  inquiryErrorMessage,
  statusBadgeClass,
  statusLabel,
  transactionMethodLabel,
} from './inquiryModeration';

interface InquiryDetailsDialogProps {
  inquiryId: number;
  onClose: () => void;
}

interface DetailSection {
  title: string;
  wide?: boolean;
  rows?: Array<[string, ReactNode]>;
  content?: ReactNode;
}

function orDash(value: string | number | null | undefined): string {
  if (value === null || value === undefined || value === '') return '\u2014';
  return String(value);
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

function formatDate(value: string | null | undefined): string {
  if (!value) return '\u2014';
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return '\u2014';
  return date.toLocaleDateString('en-PH', {
    year: 'numeric',
    month: 'short',
    day: 'numeric',
  });
}

/**
 * The ₱ prefix is added to the exact amount string the API returned.
 *
 * The backend casts the value to a two-decimal string, so it is displayed
 * as-is: no parsing, formatting or re-rounding happens here.
 */
function formatAmount(value: string | null | undefined): string {
  if (value === null || value === undefined || value === '') return '\u2014';
  return `\u20B1${value}`;
}

function interestLabel(value: boolean | null): string {
  if (value === null) return '\u2014';
  return value ? 'Yes' : 'No';
}

/**
 * The full record for one inquiry, with the two administrator actions: change
 * the workflow status, or delete the inquiry.
 *
 * The detail is fetched by id rather than handed in from the list, so a deep
 * link can open a row that is not on the page the list is showing. A failure
 * from either action is shown in place instead of closing the dialog, so the
 * administrator sees why nothing happened; the mutation hooks invalidate the
 * inquiries queries either way, so the list behind the dialog is re-read.
 */
export default function InquiryDetailsDialog({
  inquiryId,
  onClose,
}: InquiryDetailsDialogProps) {
  const { data: inquiry, isLoading, error, refetch } = useInquiry(inquiryId);
  const updateStatus = useUpdateInquiryStatus();
  const removeInquiry = useDeleteInquiry();

  const [selectedStatus, setSelectedStatus] = useState<string | null>(null);
  const [feedbackError, setFeedbackError] = useState<string | null>(null);
  const [confirmingDelete, setConfirmingDelete] = useState(false);

  const isWorking = updateStatus.isPending || removeInquiry.isPending;

  // The select mirrors the record until the administrator picks a different
  // value. Deriving it rather than copying it into state keeps the control in
  // step with a refetch after a successful update, with no effect to drift.
  const serverStatus = inquiry?.status ?? '';
  const status = selectedStatus ?? serverStatus;

  useEffect(() => {
    function onKeyDown(event: KeyboardEvent) {
      if (event.key === 'Escape' && !isWorking) onClose();
    }
    window.addEventListener('keydown', onKeyDown);
    return () => window.removeEventListener('keydown', onKeyDown);
  }, [onClose, isWorking]);

  const handleUpdateStatus = () => {
    if (!inquiry || status === '' || status === serverStatus) return;

    setFeedbackError(null);
    updateStatus.mutate(
      { id: inquiry.id, status },
      { onError: (mutationError) => setFeedbackError(inquiryErrorMessage(mutationError)) },
    );
  };

  const handleDelete = () => {
    setFeedbackError(null);
    removeInquiry.mutate(inquiryId, {
      onSuccess: onClose,
      onError: (mutationError) => setFeedbackError(inquiryErrorMessage(mutationError)),
    });
  };

  const management = inquiry ? (
    <>
      <div className="lv-action-modal-field">
        <label className="lv-action-modal-label" htmlFor="inquiry-status-select">
          Response status
        </label>
        <select
          id="inquiry-status-select"
          className="lv-filter-select"
          value={status}
          disabled={isWorking}
          onChange={(event) => setSelectedStatus(event.target.value)}
        >
          {INQUIRY_STATUSES.map((option) => (
            <option key={option.value} value={option.value}>
              {option.label}
            </option>
          ))}
        </select>
      </div>

      <div className="lv-action-modal-buttons">
        <button
          type="button"
          className="lv-action-confirm lv-action-confirm--approve"
          disabled={isWorking || status === '' || status === serverStatus}
          onClick={handleUpdateStatus}
        >
          {updateStatus.isPending ? 'Saving\u2026' : 'Update status'}
        </button>
      </div>

      <div className="lv-action-modal-field">
        {confirmingDelete ? (
          <>
            <p className="lv-action-modal-label">
              Delete this inquiry permanently? This cannot be undone.
            </p>
            <div className="lv-action-modal-buttons">
              <button
                type="button"
                className="lv-action-cancel"
                disabled={isWorking}
                onClick={() => setConfirmingDelete(false)}
              >
                Cancel
              </button>
              <button
                type="button"
                className="lv-action-confirm lv-action-confirm--reject"
                disabled={isWorking}
                onClick={handleDelete}
              >
                {removeInquiry.isPending ? 'Deleting\u2026' : 'Delete inquiry'}
              </button>
            </div>
          </>
        ) : (
          <div className="lv-action-modal-buttons">
            <button
              type="button"
              className="lv-action-confirm lv-action-confirm--reject"
              disabled={isWorking}
              onClick={() => setConfirmingDelete(true)}
            >
              Delete inquiry
            </button>
          </div>
        )}
      </div>
    </>
  ) : null;

  const sections: DetailSection[] = inquiry
    ? [
        {
          title: 'Summary',
          rows: [
            ['Request ID', `#${inquiry.id}`],
            [
              'Status',
              <span key="status" className={statusBadgeClass(inquiry.status)}>
                {statusLabel(inquiry.status)}
              </span>,
            ],
            ['Subject', orDash(inquiry.subject)],
            ['Received', formatDateTime(inquiry.created_at)],
            ['Updated', formatDateTime(inquiry.updated_at)],
          ],
        },
        {
          title: 'Buyer',
          rows: [
            ['Name', orDash(inquiry.buyer?.name)],
            ['Email', orDash(inquiry.buyer?.email)],
            ['Buyer ID', orDash(inquiry.buyer?.id)],
          ],
        },
        {
          title: 'Seller',
          rows: [
            ['Name', orDash(inquiry.seller?.name)],
            ['Email', orDash(inquiry.seller?.email)],
            ['Seller ID', orDash(inquiry.seller?.id)],
          ],
        },
        inquiry.listing
          ? {
              title: 'Listing',
              rows: [
                ['Listing ID', `#${inquiry.listing.id}`],
                ['Livestock type', orDash(inquiry.listing.livestock_type)],
                ['Breed', orDash(inquiry.listing.breed)],
              ],
            }
          : {
              title: 'Listing',
              rows: [['Listing', 'No listing linked']],
            },
        {
          title: 'Request details',
          rows: [
            ['Purchase interest', interestLabel(inquiry.purchase_interest)],
            ['Transaction method', transactionMethodLabel(inquiry.transaction_method)],
            ['Delivery method', orDash(inquiry.delivery_method)],
            ['Delivery fee', formatAmount(inquiry.delivery_fee)],
            ['Contact method', contactMethodLabel(inquiry.contact_method)],
            ['Preferred schedule', formatDate(inquiry.preferred_schedule)],
          ],
        },
        {
          title: 'Message',
          wide: true,
          content: <p className="lv-detail-value">{inquiry.message}</p>,
        },
        {
          title: 'Management',
          wide: true,
          content: management,
        },
      ]
    : [];

  return (
    <div className="lv-action-modal-overlay" onClick={() => !isWorking && onClose()}>
      <div
        className="lv-action-modal lv-action-modal--detail"
        role="dialog"
        aria-modal="true"
        aria-labelledby="inquiry-details-title"
        onClick={(event) => event.stopPropagation()}
      >
        <header className="lv-detail-header">
          <div className="lv-detail-heading">
            <h2 className="lv-action-modal-title" id="inquiry-details-title">
              Inquiry #{inquiryId}
            </h2>
            <p className="lv-action-modal-desc">
              The buyer&apos;s request and the parties involved.
            </p>
          </div>
        </header>

        <div className="lv-detail-body">
          {isLoading ? (
            <div className="lv-loading">
              <div className="loading-spinner" />
              <span>Loading inquiry details...</span>
            </div>
          ) : error ? (
            <div className="lv-error">
              <p className="lv-error-text">Failed to load inquiry details.</p>
              <button type="button" className="lv-retry-button" onClick={() => refetch()}>
                Retry
              </button>
            </div>
          ) : (
            <>
              {feedbackError && (
                <div className="lv-error">
                  <p className="lv-error-text">{feedbackError}</p>
                </div>
              )}

              <div className="lv-detail-grid">
                {sections.map((section) => (
                  <section
                    key={section.title}
                    className={`lv-detail-section${section.wide ? ' lv-detail-section--wide' : ''}`}
                  >
                    <h3 className="lv-detail-section-title">{section.title}</h3>
                    {section.content ?? (
                      <dl className="lv-detail-list">
                        {section.rows?.map(([label, value]) => (
                          <div className="lv-detail-item" key={label}>
                            <dt className="lv-detail-label">{label}</dt>
                            <dd className="lv-detail-value">{value}</dd>
                          </div>
                        ))}
                      </dl>
                    )}
                  </section>
                ))}
              </div>
            </>
          )}
        </div>

        <footer className="lv-detail-footer">
          <button
            type="button"
            className="lv-action-cancel"
            disabled={isWorking}
            onClick={onClose}
          >
            Close
          </button>
        </footer>
      </div>
    </div>
  );
}
