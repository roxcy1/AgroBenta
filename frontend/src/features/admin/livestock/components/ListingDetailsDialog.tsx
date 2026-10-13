import { useEffect } from 'react';
import type { ReactNode } from 'react';
import type { Listing } from '../api/useListings';
import { statusLabel } from './listingModeration';

interface ListingDetailsDialogProps {
  listing: Listing;
  onClose: () => void;
}

interface DetailSection {
  title: string;
  wide?: boolean;
  rows: Array<[string, ReactNode]>;
}

function orDash(value: string | number | null | undefined): string {
  if (value === null || value === undefined || value === '') return '\u2014';
  return String(value);
}

function formatCurrency(value: string | null | undefined): string {
  if (value === null || value === undefined || value === '') return '\u2014';
  const amount = parseFloat(value);
  if (Number.isNaN(amount)) return `\u20B1${value}`;
  return `\u20B1${amount.toLocaleString('en-PH', {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  })}`;
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

export default function ListingDetailsDialog({ listing, onClose }: ListingDetailsDialogProps) {
  useEffect(() => {
    function onKeyDown(event: KeyboardEvent) {
      if (event.key === 'Escape') onClose();
    }
    window.addEventListener('keydown', onKeyDown);
    return () => window.removeEventListener('keydown', onKeyDown);
  }, [onClose]);

  const sections: DetailSection[] = [
    {
      title: 'Summary',
      rows: [
        ['Listing ID', `#${listing.id}`],
        [
          'Status',
          <span key="status" className={`lv-badge lv-badge--${listing.status}`}>
            {statusLabel(listing.status)}
          </span>,
        ],
      ],
    },
    {
      title: 'Livestock',
      rows: [
        ['Type', orDash(listing.livestock_type)],
        ['Breed', orDash(listing.breed)],
        [
          'Age',
          listing.age_value !== null
            ? `${listing.age_value} ${listing.age_unit ?? ''}`.trim()
            : '\u2014',
        ],
        ['Gender', orDash(listing.gender)],
        [
          'Weight',
          listing.weight_value !== null
            ? `${listing.weight_value} ${listing.weight_unit ?? ''}`.trim()
            : '\u2014',
        ],
        ['Quantity', orDash(listing.quantity)],
      ],
    },
    {
      title: 'Price & Location',
      rows: [
        ['Asking price', formatCurrency(listing.asking_price)],
        ['Location', orDash(listing.location)],
      ],
    },
    {
      title: 'Health',
      rows: [
        ['Health status', orDash(listing.health_status)],
        ['Vaccination', orDash(listing.vaccination)],
      ],
    },
    {
      title: 'Description',
      wide: true,
      rows: [
        ['Short description', orDash(listing.short_description)],
        ['Additional notes', orDash(listing.additional_notes)],
      ],
    },
    {
      title: 'Seller',
      rows: [
        ['Name', orDash(listing.seller?.name)],
        ['Email', orDash(listing.seller?.email)],
        ['Seller ID', orDash(listing.seller?.id)],
      ],
    },
    {
      title: 'Record',
      rows: [
        ['Created', formatDateTime(listing.created_at)],
        ['Updated', formatDateTime(listing.updated_at)],
        ['Admin note', orDash(listing.admin_note)],
      ],
    },
  ];

  return (
    <div className="lv-action-modal-overlay" onClick={onClose}>
      <div
        className="lv-action-modal lv-action-modal--detail"
        role="dialog"
        aria-modal="true"
        aria-labelledby="listing-details-title"
        onClick={(event) => event.stopPropagation()}
      >
        <header className="lv-detail-header">
          <div className="lv-detail-heading">
            <h2 className="lv-action-modal-title" id="listing-details-title">
              Listing #{listing.id}
            </h2>
            <p className="lv-action-modal-desc">Full details recorded for this listing.</p>
          </div>
        </header>

        <div className="lv-detail-body">
          <div className="lv-detail-grid">
            {sections.map((section) => (
              <section
                key={section.title}
                className={`lv-detail-section${section.wide ? ' lv-detail-section--wide' : ''}`}
              >
                <h3 className="lv-detail-section-title">{section.title}</h3>
                <dl className="lv-detail-list">
                  {section.rows.map(([label, value]) => (
                    <div className="lv-detail-item" key={label}>
                      <dt className="lv-detail-label">{label}</dt>
                      <dd className="lv-detail-value">{value}</dd>
                    </div>
                  ))}
                </dl>
              </section>
            ))}
          </div>
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
