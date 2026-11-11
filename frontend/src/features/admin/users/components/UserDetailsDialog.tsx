import { useEffect } from 'react';
import type { ReactNode } from 'react';
import { CalendarDays, ClipboardList, Contact, UserRound, X } from 'lucide-react';
import type { LucideIcon } from 'lucide-react';
import type { AdminUser } from '../api/useUsers';
import { StatusBadge } from '../../components/StatusBadge';
import { formatDateTime } from '../../../../lib/format';
import '../../livestock/components/ListingDetailsDialog.css';
import './UserDetailsDialog.css';

type VerificationStatus = 'submitted' | 'pending_review' | 'approved' | 'rejected';

interface UserDetailsDialogProps {
  user: AdminUser;
  verificationStatus: VerificationStatus | null;
  onClose: () => void;
}

interface DetailSection {
  title: string;
  Icon: LucideIcon;
  wide?: boolean;
  rows: Array<[string, ReactNode]>;
}

function orDash(value: string | number | null | undefined): string {
  if (value === null || value === undefined || value === '') return '\u2014';
  return String(value);
}

function roleLabel(role: AdminUser['role']): string {
  return role === 'admin' ? 'Administrator' : 'User';
}

function capabilityLabel(capability: AdminUser['seller_capability']): string {
  return capability === 'seller' ? 'Seller' : 'Buyer';
}

export default function UserDetailsDialog({
  user,
  verificationStatus,
  onClose,
}: UserDetailsDialogProps) {
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
        ['Account ID', `#${user.id}`],
        [
          'Verification status',
          verificationStatus ? (
            <StatusBadge key="verification" status={verificationStatus} />
          ) : (
            '\u2014'
          ),
        ],
      ],
    },
    {
      title: 'Account',
      Icon: UserRound,
      rows: [
        ['Role', roleLabel(user.role)],
        ['Account type', capabilityLabel(user.seller_capability)],
        [
          'Email verification status',
          user.email_verified_at ? formatDateTime(user.email_verified_at) : 'Not verified',
        ],
      ],
    },
    {
      title: 'Contact',
      Icon: Contact,
      rows: [
        ['Name', orDash(user.name)],
        ['Email', orDash(user.email)],
      ],
    },
    {
      title: 'Record',
      Icon: CalendarDays,
      rows: [
        ['Created', formatDateTime(user.created_at)],
        ['Updated', formatDateTime(user.updated_at)],
      ],
    },
  ];

  return (
    <div className="lv-action-modal-overlay user-details-overlay listing-details-overlay" onClick={onClose}>
      <div
        className="lv-action-modal lv-action-modal--detail lv-action-modal--listing-details user-details-modal"
        role="dialog"
        aria-modal="true"
        aria-labelledby="user-details-title"
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
            <h2 className="lv-action-modal-title listing-details-title" id="user-details-title">
              {user.name}
            </h2>
            <p className="lv-action-modal-desc listing-details-subtitle">Account details for this user.</p>
          </div>
          <button
            type="button"
            className="listing-details-header-close"
            aria-label="Close user details"
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
                className={`lv-detail-section user-details-card user-details-card--${section.title.toLowerCase()}${section.wide ? ' lv-detail-section--wide' : ''}`}
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
        </div>

        <footer className="lv-detail-footer user-details-footer">
          <button type="button" className="user-details-footer-close" onClick={onClose}>
            Close
          </button>
        </footer>
      </div>
    </div>
  );
}
