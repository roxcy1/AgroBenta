import { useEffect } from 'react';
import type { ReactNode } from 'react';
import type { SellerVerification } from '../api/useSellerVerifications';
import { useSellerVerification } from '../api/useSellerVerifications';
import { statusLabel } from './verificationModeration';

interface VerificationDetailsDialogProps {
  verificationId: number;
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

function StatusBadge({ status }: { status: string }) {
  return <span className={`lv-badge lv-badge--${status}`}>{statusLabel(status)}</span>;
}

function historyTable(history: SellerVerification[]): ReactNode {
  if (history.length === 0) {
    return <p className="lv-detail-value">No prior submissions from this applicant.</p>;
  }

  return (
    <div className="lv-table-container">
      <table className="lv-table">
        <thead>
          <tr>
            <th>Status</th>
            <th>Submitted</th>
            <th>Reviewed by</th>
            <th>Admin note</th>
          </tr>
        </thead>
        <tbody>
          {history.map((entry) => (
            <tr key={entry.id}>
              <td>
                <StatusBadge status={entry.status} />
              </td>
              <td className="lv-date-cell">{formatDateTime(entry.submitted_at)}</td>
              <td>{orDash(entry.reviewer?.name)}</td>
              <td>{orDash(entry.admin_note)}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

export default function VerificationDetailsDialog({
  verificationId,
  onClose,
}: VerificationDetailsDialogProps) {
  const { data, isLoading, error, refetch } = useSellerVerification(verificationId);

  useEffect(() => {
    function onKeyDown(event: KeyboardEvent) {
      if (event.key === 'Escape') onClose();
    }
    window.addEventListener('keydown', onKeyDown);
    return () => window.removeEventListener('keydown', onKeyDown);
  }, [onClose]);

  const verification = data?.verification;
  const history = data?.history ?? [];

  const sections: DetailSection[] = verification
    ? [
        {
          title: 'Summary',
          rows: [
            ['Request ID', `#${verification.id}`],
            ['Status', <StatusBadge key="status" status={verification.status} />],
            ['Submitted', formatDateTime(verification.submitted_at)],
            ['Reviewed', formatDateTime(verification.reviewed_at)],
          ],
        },
        {
          title: 'Applicant',
          rows: [
            ['Name', orDash(verification.seller?.name)],
            ['Email', orDash(verification.seller?.email)],
            ['Seller ID', orDash(verification.seller?.id)],
          ],
        },
        {
          title: 'Business',
          rows: [
            ['Business name', orDash(verification.business_name)],
            ['Location', orDash(verification.business_location)],
            ['Description', orDash(verification.business_description)],
          ],
        },
        {
          title: 'Identity document',
          rows: [['Reference', orDash(verification.id_document_ref)]],
        },
        {
          title: 'Decision',
          rows: [
            ['Reviewed by', orDash(verification.reviewer?.name)],
            ['Admin note', orDash(verification.admin_note)],
          ],
        },
        {
          title: 'Record',
          rows: [
            ['Created', formatDateTime(verification.created_at)],
            ['Updated', formatDateTime(verification.updated_at)],
          ],
        },
        {
          title: 'Review history',
          wide: true,
          content: historyTable(history),
        },
      ]
    : [];

  return (
    <div className="lv-action-modal-overlay" onClick={onClose}>
      <div
        className="lv-action-modal lv-action-modal--detail"
        role="dialog"
        aria-modal="true"
        aria-labelledby="verification-details-title"
        onClick={(event) => event.stopPropagation()}
      >
        <header className="lv-detail-header">
          <div className="lv-detail-heading">
            <h2 className="lv-action-modal-title" id="verification-details-title">
              Verification #{verificationId}
            </h2>
            <p className="lv-action-modal-desc">
              Full details and prior submissions for this applicant.
            </p>
          </div>
        </header>

        <div className="lv-detail-body">
          {isLoading ? (
            <div className="lv-loading">
              <div className="loading-spinner" />
              <span>Loading verification details...</span>
            </div>
          ) : error ? (
            <div className="lv-error">
              <p className="lv-error-text">Failed to load verification details.</p>
              <button type="button" className="lv-retry-button" onClick={() => refetch()}>
                Retry
              </button>
            </div>
          ) : (
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
          )}
        </div>

        <footer className="lv-detail-footer">
          <button type="button" className="lv-action-cancel" onClick={onClose}>
            Close
          </button>
        </footer>
      </div>
    </div>
  );
}
