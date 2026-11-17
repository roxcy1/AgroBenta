import { useEffect } from 'react';
import type { ReactNode } from 'react';
import {
  Beef,
  CalendarDays,
  ClipboardList,
  ExternalLink,
  FileText,
  HeartPulse,
  Image as ImageIcon,
  Layers,
  MapPin,
  Scale,
  Store,
  Tag,
  PackageCheck,
  UsersRound,
  X,
} from 'lucide-react';
import type { LucideIcon } from 'lucide-react';
import type { Listing } from '../api/useListings';
import ListingPhotos from './ListingPhotos';
import { StatusBadge } from '../../components/StatusBadge';
import { formatDateTime, formatPeso } from '../../../../lib/format';
import { livestockTypeLabel } from '../api/useLivestockTypes';
import type { LivestockTypeOption } from '../api/useLivestockTypes';
import './ListingDetailsDialog.css';

interface ListingDetailsDialogProps {
  listing: Listing;
  livestockTypes: LivestockTypeOption[];
  onClose: () => void;
  onReconcile?: () => void;
}

interface DetailSection {
  title: string;
  Icon: LucideIcon;
  wide?: boolean;
  rows: Array<[string, ReactNode, LucideIcon?]>;
}

function orDash(value: string | number | null | undefined): string {
  if (value === null || value === undefined || value === '') return '\u2014';
  return String(value);
}

export default function ListingDetailsDialog({ listing, livestockTypes, onClose, onReconcile }: ListingDetailsDialogProps) {
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
      Icon: ClipboardList,
      rows: [
        ['Listing ID', `#${listing.id}`],
        [
          'Status',
          <StatusBadge key="status" status={listing.status} />,
        ],
      ],
    },
    {
      title: 'Livestock',
      Icon: Beef,
      rows: [
        ['Type', orDash(livestockTypeLabel(listing.livestock_type, livestockTypes)), Tag],
        ['Breed', orDash(listing.breed), Layers],
        [
          'Age',
          listing.age_value !== null
            ? `${listing.age_value} ${listing.age_unit ?? ''}`.trim()
            : '\u2014',
          CalendarDays,
        ],
        ['Gender', orDash(listing.gender), UsersRound],
        [
          'Weight',
          listing.weight_value !== null
            ? `${listing.weight_value} ${listing.weight_unit ?? ''}`.trim()
            : '\u2014',
          Scale,
        ],
      ],
    },
    {
      title: 'Inventory',
      Icon: PackageCheck,
      rows: [
        ['Total quantity', listing.inventory_reconciliation_required ? 'Requires reconciliation' : orDash(listing.total_quantity)],
        ['Reserved', orDash(listing.reserved_quantity)],
        ['Sold through AgroBenta', orDash(listing.platform_sold_quantity)],
        ['Sold externally', orDash(listing.externally_sold_quantity)],
        ['Total sold', orDash(listing.sold_quantity)],
        ['Available', listing.inventory_reconciliation_required ? 'Requires reconciliation' : orDash(listing.available_quantity)],
        ['Inventory status', listing.inventory_reconciliation_required ? 'Reconciliation required' : 'Verified'],
        ...(listing.inventory_reconciliation_required
          ? [['Preserved legacy quantity', orDash(listing.legacy_quantity_snapshot)] as [string, ReactNode]]
          : []),
      ],
    },
    {
      title: 'Price & Location',
      Icon: MapPin,
      rows: [
        ['Asking price', formatPeso(listing.asking_price)],
        ['Location', orDash(listing.location)],
      ],
    },
    {
      title: 'Health',
      Icon: HeartPulse,
      rows: [
        ['Health status', orDash(listing.health_status)],
        ['Vaccination', orDash(listing.vaccination)],
      ],
    },
    {
      title: 'Description',
      Icon: FileText,
      wide: true,
      rows: [
        ['Short description', orDash(listing.short_description)],
        ['Additional notes', orDash(listing.additional_notes)],
      ],
    },
    {
      title: 'Seller',
      Icon: Store,
      rows: [
        ['Name', orDash(listing.seller?.name)],
        ['Email', orDash(listing.seller?.email)],
        ['Seller ID', orDash(listing.seller?.id)],
      ],
    },
    {
      title: 'Record',
      Icon: ClipboardList,
      rows: [
        ['Created', formatDateTime(listing.created_at)],
        ['Updated', formatDateTime(listing.updated_at)],
        ['Admin note', orDash(listing.admin_note)],
        ...(listing.latest_inventory_reconciliation
          ? [
              ['Last reconciled by', orDash(listing.latest_inventory_reconciliation.admin?.name)] as [string, ReactNode],
              ['Reconciled', formatDateTime(listing.latest_inventory_reconciliation.created_at)] as [string, ReactNode],
              ['Reconciliation reason', listing.latest_inventory_reconciliation.reason] as [string, ReactNode],
            ]
          : []),
      ],
    },
  ];

  return (
    <div className="lv-action-modal-overlay listing-details-overlay" onClick={onClose}>
      <div
        className="lv-action-modal lv-action-modal--detail lv-action-modal--listing-details"
        role="dialog"
        aria-modal="true"
        aria-labelledby="listing-details-title"
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
            <h2 className="lv-action-modal-title listing-details-title" id="listing-details-title">
              Listing #{listing.id}
            </h2>
            <p className="lv-action-modal-desc listing-details-subtitle">Full details recorded for this listing.</p>
          </div>
          <button
            type="button"
            className="listing-details-header-close"
            aria-label="Close listing details"
            onClick={onClose}
          >
            <X aria-hidden="true" />
          </button>
        </header>

        <div className="lv-detail-body">
          <section className="lv-detail-section lv-detail-section--photos">
            <div className="listing-details-section-heading">
              <h3 className="lv-detail-section-title">
                <ImageIcon aria-hidden="true" />
                Photos
              </h3>
              {listing.photos[0] && (
                <a
                  className="lv-photos-open listing-details-open-full-size"
                  href={listing.photos[0]}
                  target="_blank"
                  rel="noopener noreferrer"
                >
                  <ExternalLink aria-hidden="true" />
                  Open full size
                </a>
              )}
            </div>
            <ListingPhotos
              photos={listing.photos}
              label={`Listing #${listing.id}`}
              showOpenFullSize={false}
            />
          </section>

          <div className="lv-detail-grid">
            {sections.map((section) => {
              const SectionIcon = section.Icon;

              return (
              <section
                key={section.title}
                className={`lv-detail-section${section.wide ? ' lv-detail-section--wide' : ''}`}
              >
                <h3 className="lv-detail-section-title">
                  <SectionIcon aria-hidden="true" />
                  {section.title}
                </h3>
                <dl className="lv-detail-list">
                  {section.rows.map(([label, value, RowIcon]) => (
                    <div className="lv-detail-item" key={label}>
                      <dt className="lv-detail-label">
                        {RowIcon && <RowIcon className="listing-details-field-icon" aria-hidden="true" />}
                        {label}
                      </dt>
                      <dd className="lv-detail-value">{value}</dd>
                    </div>
                  ))}
                </dl>
              </section>
              );
            })}
          </div>
        </div>

        <footer className="lv-detail-footer">
          {listing.inventory_reconciliation_required && onReconcile && (
            <button
              type="button"
              className="lv-action-confirm lv-action-confirm--approve"
              onClick={onReconcile}
            >
              Reconcile inventory
            </button>
          )}
          <button type="button" className="listing-details-footer-close" onClick={onClose}>
            Close
          </button>
        </footer>
      </div>
    </div>
  );
}
