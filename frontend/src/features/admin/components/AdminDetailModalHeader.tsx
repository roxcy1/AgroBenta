import { X } from 'lucide-react';
import '../livestock/components/ListingDetailsDialog.css';

interface AdminDetailModalHeaderProps {
  title: string;
  subtitle: string;
  titleId: string;
  closeLabel: string;
  closeDisabled?: boolean;
  onClose: () => void;
}

/** Shared AgroBenta title bar for large administrator detail and review modals. */
export function AdminDetailModalHeader({
  title,
  subtitle,
  titleId,
  closeLabel,
  closeDisabled = false,
  onClose,
}: AdminDetailModalHeaderProps) {
  return (
    <header className="lv-detail-header listing-details-header">
      <div className="listing-details-brand" aria-label="AgroBenta">
        <span className="listing-details-brand-wordmark">
          Agro<span>Benta</span>
        </span>
      </div>
      <span className="listing-details-header-divider" aria-hidden="true" />
      <div className="lv-detail-heading">
        <h2 className="lv-action-modal-title listing-details-title" id={titleId}>
          {title}
        </h2>
        <p className="lv-action-modal-desc listing-details-subtitle">{subtitle}</p>
      </div>
      <button
        type="button"
        className="listing-details-header-close"
        aria-label={closeLabel}
        disabled={closeDisabled}
        onClick={onClose}
      >
        <X aria-hidden="true" />
      </button>
    </header>
  );
}
