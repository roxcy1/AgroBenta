import { useEffect, useState } from 'react';
import type { ReactNode } from 'react';
import type { SellerVerification, VerificationDocumentType } from '../api/useSellerVerifications';
import {
  fetchVerificationDocument,
  useSellerVerification,
} from '../api/useSellerVerifications';
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

/**
 * One evidence document: whether it is on file, and a View action that streams
 * the bytes behind the authenticated admin endpoint.
 *
 * The bytes are fetched on demand rather than listed, because the API never
 * returns a URL — the private disk has none. A `URL.createObjectURL` preview is
 * revoked when the lightbox closes so an open document does not leak a blob.
 */
function DocumentViewer({
  verificationId,
  type,
  label,
  present,
}: {
  verificationId: number;
  type: VerificationDocumentType;
  label: string;
  present: boolean;
}) {
  const [objectUrl, setObjectUrl] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState(false);

  useEffect(() => {
    return () => {
      if (objectUrl) URL.revokeObjectURL(objectUrl);
    };
  }, [objectUrl]);

  async function open() {
    setLoading(true);
    setError(false);
    try {
      const blob = await fetchVerificationDocument(verificationId, type);
      setObjectUrl(URL.createObjectURL(blob));
    } catch {
      setError(true);
    } finally {
      setLoading(false);
    }
  }

  function close() {
    if (objectUrl) URL.revokeObjectURL(objectUrl);
    setObjectUrl(null);
  }

  return (
    <div className="lv-detail-item">
      <dt className="lv-detail-label">{label}</dt>
      <dd className="lv-detail-value">
        {present ? (
          <button type="button" className="lv-action-cancel" onClick={open} disabled={loading}>
            {loading ? 'Loading…' : 'View'}
          </button>
        ) : (
          <span>{'\u2014'} Not provided</span>
        )}
        {error ? <span className="lv-error-text"> Failed to load document.</span> : null}
      </dd>

      {objectUrl ? (
        <div className="lv-action-modal-overlay" onClick={close}>
          <div
            className="lv-action-modal lv-action-modal--detail"
            role="dialog"
            aria-modal="true"
            aria-label={`${label} document`}
            onClick={(event) => event.stopPropagation()}
          >
            <header className="lv-detail-header">
              <h2 className="lv-action-modal-title">{label}</h2>
            </header>
            <div className="lv-detail-body">
              <img src={objectUrl} alt={label} style={{ maxWidth: '100%' }} />
            </div>
            <footer className="lv-detail-footer">
              <button type="button" className="lv-action-cancel" onClick={close}>
                Close
              </button>
            </footer>
          </div>
        </div>
      ) : null}
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
          title: 'Government-issued ID',
          content: (
            <dl className="lv-detail-list">
              <DocumentViewer
                verificationId={verification.id}
                type="id_document"
                label="Government-issued ID"
                present={verification.has_id_document}
              />
            </dl>
          ),
        },
        {
          title: 'Selfie holding ID',
          content: (
            <dl className="lv-detail-list">
              <DocumentViewer
                verificationId={verification.id}
                type="selfie"
                label="Selfie holding ID"
                present={verification.has_selfie}
              />
            </dl>
          ),
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
