import { useEffect, useState } from 'react';
import type { ReactNode } from 'react';
import { AlertTriangle, CalendarDays, ClipboardList, ShieldAlert, UserRound, X } from 'lucide-react';
import type { LucideIcon } from 'lucide-react';
import { useToast } from '../../../../lib/toast/ToastProvider';
import { formatDateTime } from '../../../../lib/format';
import { StatusBadge } from '../../components/StatusBadge';
import { DocumentViewer } from '../../seller-verification/components/VerificationDocuments';
import {
  fetchUserReportEvidence,
  useDeactivateFromUserReport,
  useDismissUserReport,
  useUserReport,
} from '../api/useUserReports';
import { apiUserErrorMessage } from '../userValidation';
import '../../livestock/components/ListingDetailsDialog.css';
import '../../users/components/UserDetailsDialog.css';

interface UserReportReviewDialogProps {
  reportId: number;
  onClose: () => void;
}

interface DetailSection {
  title: string;
  Icon: LucideIcon;
  rows: Array<[string, ReactNode]>;
}

export default function UserReportReviewDialog({
  reportId,
  onClose,
}: UserReportReviewDialogProps) {
  const { data: report, isLoading, error, refetch } = useUserReport(reportId);
  const dismissReport = useDismissUserReport();
  const deactivateAccount = useDeactivateFromUserReport();
  const toast = useToast();
  const [action, setAction] = useState<'dismiss' | 'deactivate' | null>(null);
  const [note, setNote] = useState('');
  const [reason, setReason] = useState('');
  const [actionError, setActionError] = useState<string | null>(null);

  useEffect(() => {
    function onKeyDown(event: KeyboardEvent) {
      if (event.key === 'Escape' && !dismissReport.isPending && !deactivateAccount.isPending) {
        onClose();
      }
    }
    window.addEventListener('keydown', onKeyDown);
    return () => window.removeEventListener('keydown', onKeyDown);
  }, [onClose, dismissReport.isPending, deactivateAccount.isPending]);

  function handleDismiss() {
    if (!report) return;
    setActionError(null);
    dismissReport.mutate(
      { id: report.id, adminNote: note },
      {
        onSuccess: () => {
          toast.success('Report dismissed.');
          onClose();
        },
        onError: (mutationError) => {
          setActionError(
            apiUserErrorMessage(mutationError, 'Unable to dismiss this report. Please try again.'),
          );
        },
      },
    );
  }

  function handleDeactivate() {
    if (!report || reason.trim().length < 5) return;
    setActionError(null);
    deactivateAccount.mutate(
      { id: report.id, reason: reason.trim() },
      {
        onSuccess: () => {
          toast.success('Report actioned and account deactivated.');
          onClose();
        },
        onError: (mutationError) => {
          setActionError(
            apiUserErrorMessage(
              mutationError,
              'Unable to deactivate this account from the report. Please try again.',
            ),
          );
        },
      },
    );
  }

  const isPending = dismissReport.isPending || deactivateAccount.isPending;

  if (isLoading) {
    return (
      <div className="lv-action-modal-overlay" onClick={onClose}>
        <div
          className="lv-action-modal lv-action-modal--detail user-report-review-modal"
          role="dialog"
          aria-modal="true"
          aria-label="Loading report"
          onClick={(event) => event.stopPropagation()}
        >
          <div className="lv-loading">
            <div className="loading-spinner" />
            <span>Loading report...</span>
          </div>
        </div>
      </div>
    );
  }

  if (error || !report) {
    return (
      <div className="lv-action-modal-overlay" onClick={onClose}>
        <div
          className="lv-action-modal lv-action-modal--detail user-report-review-modal"
          role="dialog"
          aria-modal="true"
          aria-label="Report unavailable"
          onClick={(event) => event.stopPropagation()}
        >
          <div className="lv-error">
            <p className="lv-error-text">Failed to load this report.</p>
            <button type="button" className="lv-retry-button" onClick={() => refetch()}>
              Retry
            </button>
            <button type="button" className="lv-action-cancel" onClick={onClose}>
              Close
            </button>
          </div>
        </div>
      </div>
    );
  }

  const sections: DetailSection[] = [
    {
      title: 'Parties',
      Icon: UserRound,
      rows: [
        ['Reporter', report.reporter?.name ?? '\u2014'],
        [
          'Reported user',
          report.reported_user
            ? `${report.reported_user.name} (${report.reported_user.status === 'deactivated' ? 'Deactivated' : 'Active'})`
            : '\u2014',
        ],
      ],
    },
    {
      title: 'Report',
      Icon: ShieldAlert,
      rows: [
        ['Reason', report.reason_label],
        ['Status', <StatusBadge key="status" status={report.status} />],
        ['Submitted', formatDateTime(report.created_at)],
      ],
    },
    {
      title: 'Review',
      Icon: CalendarDays,
      rows: [
        ['Reviewer', report.reviewer?.name ?? '\u2014'],
        ['Reviewed', report.reviewed_at ? formatDateTime(report.reviewed_at) : '\u2014'],
        ['Administrative note', report.admin_note ?? '\u2014'],
      ],
    },
    {
      title: 'Description',
      Icon: ClipboardList,
      rows: [['Reported issue', report.description]],
    },
  ];

  return (
    <div className="lv-action-modal-overlay" onClick={() => { if (!isPending) onClose(); }}>
      <div
        className="lv-action-modal lv-action-modal--detail lv-action-modal--listing-details user-report-review-modal"
        role="dialog"
        aria-modal="true"
        aria-labelledby="user-report-review-title"
        onClick={(event) => event.stopPropagation()}
      >
        <header className="lv-detail-header listing-details-header">
          <div className="listing-details-brand" aria-label="AgroBenta">
            <span className="listing-details-brand-wordmark">
              Agro<span>Benta</span>
            </span>
          </div>
          <span className="listing-details-header-divider" aria-hidden="true" />
          <div className="lv-detail-heading">
            <h2 className="lv-action-modal-title listing-details-title" id="user-report-review-title">
              Report #{report.id}
            </h2>
            <p className="lv-action-modal-desc listing-details-subtitle">
              Review the report before taking action.
            </p>
          </div>
          <button
            type="button"
            className="listing-details-header-close"
            aria-label="Close report review"
            disabled={isPending}
            onClick={onClose}
          >
            <X aria-hidden="true" />
          </button>
        </header>

        <div className="lv-detail-body user-details-body">
          <div className="lv-detail-grid user-details-grid">
            {sections.map((section) => {
              const SectionIcon = section.Icon;
              return (
                <section
                  key={section.title}
                  className="lv-detail-section user-details-card"
                >
                  <h3 className="lv-detail-section-title user-details-section-title">
                    <SectionIcon aria-hidden="true" />
                    {section.title}
                  </h3>
                  <dl className="lv-detail-list user-details-list">
                    {section.rows.map(([label, value]) => (
                      <div className="lv-detail-item user-details-item" key={label}>
                        <dt className="lv-detail-label user-details-label">{label}</dt>
                        <dd className="lv-detail-value user-details-value">{value}</dd>
                      </div>
                    ))}
                  </dl>
                </section>
              );
            })}
          </div>

          <section className="lv-detail-section user-details-card user-report-evidence-section">
            <h3 className="lv-detail-section-title user-details-section-title">
              <AlertTriangle aria-hidden="true" />
              Evidence
            </h3>
            {report.has_evidence ? (
              <dl className="verification-document-grid">
                <DocumentViewer
                  fetchDocument={() => fetchUserReportEvidence(report.id)}
                  label="Report screenshot"
                  present
                  preview
                />
              </dl>
            ) : (
              <p className="lv-detail-value user-details-value">No screenshot was provided.</p>
            )}
          </section>

          {actionError && (
            <div className="lv-error user-report-action-error" role="alert">
              <p className="lv-error-text">{actionError}</p>
            </div>
          )}

          {action === 'dismiss' && (
            <section className="user-report-action-panel" aria-label="Dismiss report">
              <label className="users-reason-label" htmlFor="dismiss-report-note">
                Administrative note (optional)
              </label>
              <textarea
                id="dismiss-report-note"
                className="users-reason-input"
                rows={3}
                maxLength={1000}
                value={note}
                disabled={isPending}
                onChange={(event) => setNote(event.target.value)}
              />
              <div className="user-report-action-buttons">
                <button
                  type="button"
                  className="lv-action-cancel"
                  disabled={isPending}
                  onClick={() => setAction(null)}
                >
                  Cancel
                </button>
                <button
                  type="button"
                  className="lv-action-confirm"
                  disabled={isPending}
                  onClick={handleDismiss}
                >
                  {dismissReport.isPending ? 'Dismissing…' : 'Confirm Dismissal'}
                </button>
              </div>
            </section>
          )}

          {action === 'deactivate' && (
            <section className="user-report-action-panel" aria-label="Deactivate reported account">
              {(report.reported_user?.pending_transactions_count ?? 0) > 0 && (
                <p className="users-deactivate-warning" role="alert">
                  This account is part of {report.reported_user?.pending_transactions_count} pending
                  transaction{(report.reported_user?.pending_transactions_count ?? 0) === 1 ? '' : 's'}.
                  Transaction records and reserved stock will be preserved; nothing is cancelled
                  automatically.
                </p>
              )}
              <label className="users-reason-label" htmlFor="deactivate-report-reason">
                Administrative reason
              </label>
              <textarea
                id="deactivate-report-reason"
                className="users-reason-input"
                rows={3}
                maxLength={1000}
                value={reason}
                disabled={isPending}
                onChange={(event) => setReason(event.target.value)}
              />
              <p className="users-reason-help">
                Required. This deactivates the reported account and marks the report actioned.
              </p>
              <div className="user-report-action-buttons">
                <button
                  type="button"
                  className="lv-action-cancel"
                  disabled={isPending}
                  onClick={() => setAction(null)}
                >
                  Cancel
                </button>
                <button
                  type="button"
                  className="lv-action-confirm"
                  disabled={isPending || reason.trim().length < 5}
                  onClick={handleDeactivate}
                >
                  {deactivateAccount.isPending ? 'Deactivating…' : 'Confirm Deactivation'}
                </button>
              </div>
            </section>
          )}
        </div>

        <footer className="lv-detail-footer user-details-footer user-report-review-footer">
          <button type="button" className="user-details-footer-close" onClick={onClose} disabled={isPending}>
            Close
          </button>
          {report.status === 'pending' && (
            <div className="user-report-review-actions">
              <button
                type="button"
                className="lv-action-cancel"
                disabled={isPending}
                onClick={() => {
                  setAction('dismiss');
                  setActionError(null);
                }}
              >
                Dismiss Report
              </button>
              <button
                type="button"
                className="lv-action-confirm users-delete-confirm"
                disabled={isPending}
                onClick={() => {
                  setAction('deactivate');
                  setActionError(null);
                }}
              >
                Deactivate Account
              </button>
            </div>
          )}
        </footer>
      </div>
    </div>
  );
}
