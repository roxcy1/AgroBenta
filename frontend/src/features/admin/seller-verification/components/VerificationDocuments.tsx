import { useEffect, useState } from 'react';
import type { SellerVerification } from '../api/useSellerVerifications';
import {
  fetchVerificationDocument,
  fetchVerificationFarmPhoto,
} from '../api/useSellerVerifications';
import { applicantDeclaredNoBackImage } from './verificationDetails';
import { VerificationModalHeader } from './VerificationModalHeader';

/**
 * One evidence document: whether it is on file, and a way to see it. The bytes
 * come from the authenticated admin endpoint, never from a URL, so they are
 * fetched with the admin token and shown through `URL.createObjectURL`, which
 * is revoked as soon as the image is no longer on screen.
 *
 * - Default: a View button that fetches on demand and opens the lightbox.
 * - `preview`: fetches on mount and shows an inline thumbnail; clicking the
 *   thumbnail opens the same lightbox at full size.
 *
 * The lightbox handles Escape itself, in the capture phase, so closing it never
 * also closes the dialog it sits inside.
 */
export function DocumentViewer({
  fetchDocument,
  label,
  present,
  preview = false,
}: {
  fetchDocument: () => Promise<Blob>;
  label: string;
  present: boolean;
  preview?: boolean;
}) {
  const [objectUrl, setObjectUrl] = useState<string | null>(null);
  const [lightbox, setLightbox] = useState(false);
  const [loading, setLoading] = useState(preview && present);
  const [error, setError] = useState(false);

  useEffect(() => {
    return () => {
      if (objectUrl) URL.revokeObjectURL(objectUrl);
    };
  }, [objectUrl]);

  useEffect(() => {
    if (!preview || !present) return;

    let cancelled = false;
    fetchDocument()
      .then((blob) => {
        if (!cancelled) setObjectUrl(URL.createObjectURL(blob));
      })
      .catch(() => {
        if (!cancelled) setError(true);
      })
      .finally(() => {
        if (!cancelled) setLoading(false);
      });

    return () => {
      cancelled = true;
    };
    // `fetchDocument` is an inline closure that changes every render; the
    // document it reads is fixed for the lifetime of the dialog.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [preview, present]);

  useEffect(() => {
    if (!lightbox) return;

    function onKeyDown(event: KeyboardEvent) {
      if (event.key !== 'Escape') return;
      event.stopPropagation();
      closeLightbox();
    }
    window.addEventListener('keydown', onKeyDown, true);
    return () => window.removeEventListener('keydown', onKeyDown, true);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [lightbox, preview]);

  async function open() {
    setLoading(true);
    setError(false);
    try {
      const blob = await fetchDocument();
      setObjectUrl(URL.createObjectURL(blob));
      setLightbox(true);
    } catch {
      setError(true);
    } finally {
      setLoading(false);
    }
  }

  function closeLightbox() {
    setLightbox(false);
    // A preview keeps its image for the inline thumbnail; an on-demand view
    // releases the bytes as soon as it is closed.
    if (!preview) setObjectUrl(null);
  }

  return (
    <div className="lv-detail-item">
      <dt className="lv-detail-label">{label}</dt>
      <dd className="lv-detail-value">
        {!present ? (
          <span>{'—'} Not provided</span>
        ) : preview ? (
          objectUrl ? (
            <button
              type="button"
              className="verification-document-thumb"
              onClick={() => setLightbox(true)}
              aria-label={`View ${label} full size`}
            >
              <img src={objectUrl} alt={label} />
            </button>
          ) : loading ? (
            <span>Loading…</span>
          ) : null
        ) : (
          <button type="button" className="lv-action-cancel" onClick={open} disabled={loading}>
            {loading ? 'Loading…' : 'View'}
          </button>
        )}
        {error ? <span className="lv-error-text"> Failed to load document.</span> : null}
      </dd>

      {lightbox && objectUrl ? (
        <div
          className="lv-action-modal-overlay listing-details-overlay verification-document-overlay"
          onClick={closeLightbox}
        >
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
              onClose={closeLightbox}
            />
            <div className="lv-detail-body verification-document-body">
              <img className="verification-document-image" src={objectUrl} alt={label} />
            </div>
            <footer className="lv-detail-footer listing-details-footer">
              <button type="button" className="listing-details-footer-close" onClick={closeLightbox}>
                Close
              </button>
            </footer>
          </div>
        </div>
      ) : null}
    </div>
  );
}

/**
 * Every document an application can carry, as inline previews. Used by the
 * Approve / Reject dialog so the decision is made against the evidence itself.
 */
export function VerificationDocumentGallery({ verification }: { verification: SellerVerification }) {
  return (
    <dl className="verification-document-grid">
      <DocumentViewer
        preview
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
          preview
          fetchDocument={() => fetchVerificationDocument(verification.id, 'id_document_back')}
          label="Government ID — Back"
          present={verification.has_id_document_back}
        />
      )}
      <DocumentViewer
        preview
        fetchDocument={() => fetchVerificationDocument(verification.id, 'proof_of_address')}
        label="Proof of address"
        present={verification.has_proof_of_address}
      />
      <DocumentViewer
        preview
        fetchDocument={() => fetchVerificationDocument(verification.id, 'selfie')}
        label="Selfie holding ID"
        present={verification.has_selfie}
      />
      {verification.farm_photo_ids.map((photoId, index) => (
        <DocumentViewer
          preview
          key={photoId}
          fetchDocument={() => fetchVerificationFarmPhoto(verification.id, photoId)}
          label={`Farm photo ${index + 1}`}
          present
        />
      ))}
    </dl>
  );
}
