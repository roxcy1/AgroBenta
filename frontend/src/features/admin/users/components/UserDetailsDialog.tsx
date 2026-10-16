import { useEffect } from 'react';
import type { ReactNode } from 'react';
import type { AdminUser } from '../api/useUsers';

type VerificationStatus = 'submitted' | 'pending_review' | 'approved' | 'rejected';

interface UserDetailsDialogProps {
  user: AdminUser;
  verificationStatus: VerificationStatus | null;
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

function roleLabel(role: AdminUser['role']): string {
  return role === 'admin' ? 'Administrator' : 'User';
}

function capabilityLabel(capability: AdminUser['seller_capability']): string {
  return capability === 'seller' ? 'Seller' : 'Buyer';
}

function verificationLabel(status: VerificationStatus): string {
  switch (status) {
    case 'submitted':
      return 'Submitted';
    case 'pending_review':
      return 'Pending Review';
    case 'approved':
      return 'Approved';
    case 'rejected':
      return 'Rejected';
  }
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
      rows: [
        ['Account ID', `#${user.id}`],
        [
          'Verification status',
          verificationStatus ? (
            <span key="verification" className={`lv-badge lv-badge--${verificationStatus}`}>
              {verificationLabel(verificationStatus)}
            </span>
          ) : (
            '\u2014'
          ),
        ],
      ],
    },
    {
      title: 'Account',
      rows: [
        ['Role', roleLabel(user.role)],
        ['Account type', capabilityLabel(user.seller_capability)],
        ['Email verified', user.email_verified_at ? formatDateTime(user.email_verified_at) : 'Not verified'],
      ],
    },
    {
      title: 'Contact',
      rows: [
        ['Name', orDash(user.name)],
        ['Email', orDash(user.email)],
      ],
    },
    {
      title: 'Record',
      rows: [
        ['Created', formatDateTime(user.created_at)],
        ['Updated', formatDateTime(user.updated_at)],
      ],
    },
  ];

  return (
    <div className="lv-action-modal-overlay" onClick={onClose}>
      <div
        className="lv-action-modal lv-action-modal--detail"
        role="dialog"
        aria-modal="true"
        aria-labelledby="user-details-title"
        onClick={(event) => event.stopPropagation()}
      >
        <header className="lv-detail-header">
          <div className="lv-detail-heading">
            <h2 className="lv-action-modal-title" id="user-details-title">
              {user.name}
            </h2>
            <p className="lv-action-modal-desc">Account details for this user.</p>
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
