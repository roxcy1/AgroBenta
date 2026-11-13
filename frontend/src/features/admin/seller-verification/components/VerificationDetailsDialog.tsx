import { useEffect, useState } from 'react';
import type { ReactNode } from 'react';
import type { SellerVerification } from '../api/useSellerVerifications';
import {
  fetchVerificationDocument,
  fetchVerificationFarmPhoto,
  useSellerVerification,
} from '../api/useSellerVerifications';
import { StatusBadge } from '../../components/StatusBadge';
import { formatDateTime } from '../../../../lib/format';
import {
  applicantDeclaredNoBackImage,
  governmentIdTypeLabel,
} from './verificationDetails';
import { VerificationModalHeader } from './VerificationModalHeader';

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
  fetchDocument,
  label,
  present,
}: {
  fetchDocument: () => Promise<Blob>;
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
      const blob = await fetchDocument();
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
        <div className="lv-action-modal-overlay listing-details-overlay verification-document-overlay" onClick={close}>
          <div
            className="lv-action-modal lv-action-modal--detail lv-action-modal--listing-details verification-document-modal"
            role="dialog"
            aria-modal="true"
            aria-label={`${label} document`}
            onClick={(event) => event.stopPropagation()}
          >
            <VerificationModalHeader
              title={label}
              subtitle="Secure seller verification document."
              titleId="verification-document-title"
              closeLabel="Close document preview"
              onClose={close}
            />
            <div className="lv-detail-body verification-document-body">
              <img className="verification-document-image" src={objectUrl} alt={label} />
            </div>
            <footer className="lv-detail-footer listing-details-footer">
              <button type="button" className="listing-details-footer-close" onClick={close}>
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
            ['Phone number', orDash(verification.phone)],
            ['Address', orDash(verification.address)],
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
          title: 'Government ID information',
          rows: [
            ['ID type', governmentIdTypeLabel(verification.government_id_type)],
            ...(verification.government_id_type === 'others'
              ? [['Specify Government ID', orDash(verification.government_id_description)] as [string, ReactNode]]
              : []),
            ['Reference', orDash(verification.id_document_ref)],
          ],
        },
        {
          title: 'Government ID images',
          content: (
            <dl className="lv-detail-list">
              <DocumentViewer
                fetchDocument={() => fetchVerificationDocument(verification.id, 'id_document_front')}
                label="Government ID — Front"
                present={verification.has_id_document_front || verification.has_id_document}
              />
              {applicantDeclaredNoBackImage(verification) ? (
                <div className="lv-detail-item">
                  <dt className="lv-detail-label">Government ID — Back</dt>
                  <dd className="lv-detail-value">Applicant declared no back image</dd>
                </div>
              ) : (
                <DocumentViewer
                  fetchDocument={() => fetchVerificationDocument(verification.id, 'id_document_back')}
                  label="Government ID — Back"
                  present={verification.has_id_document_back}
                />
              )}
            </dl>
          ),
        },
        {
          title: 'Proof of address',
          content: (
            <dl className="lv-detail-list">
              <DocumentViewer
                fetchDocument={() => fetchVerificationDocument(verification.id, 'proof_of_address')}
                label="Proof of address"
                present={verification.has_proof_of_address}
              />
            </dl>
          ),
        },
        {
          title: 'Selfie holding ID',
          content: (
            <dl className="lv-detail-list">
              <DocumentViewer
                fetchDocument={() => fetchVerificationDocument(verification.id, 'selfie')}
                label="Selfie holding ID"
                present={verification.has_selfie}
              />
            </dl>
          ),
        },
        {
          title: 'Farm photos',
          content:
            verification.farm_photo_ids.length === 0 ? (
              <p className="lv-detail-value">{'—'} Not provided</p>
            ) : (
              <dl className="lv-detail-list">
                {verification.farm_photo_ids.map((photoId, index) => (
                  <DocumentViewer
                    key={photoId}
                    fetchDocument={() => fetchVerificationFarmPhoto(verification.id, photoId)}
                    label={`Farm photo ${index + 1}`}
                    present
                  />
                ))}
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
    <div className="lv-action-modal-overlay listing-details-overlay verification-details-overlay" onClick={onClose}>
      <div
        className="lv-action-modal lv-action-modal--detail lv-action-modal--listing-details verification-details-modal"
        role="dialog"
        aria-modal="true"
        aria-labelledby="verification-details-title"
        onClick={(event) => event.stopPropagation()}
      >
        <VerificationModalHeader
          title={`Verification #${verificationId}`}
          subtitle="Full details and prior submissions for this applicant."
          titleId="verification-details-title"
          closeLabel="Close verification details"
          onClose={onClose}
        />

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

        <footer className="lv-detail-footer listing-details-footer">
          <button type="button" className="listing-details-footer-close" onClick={onClose}>
            Close
          </button>
        </footer>
      </div>
    </div>
  );
}
