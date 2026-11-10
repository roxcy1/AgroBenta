import { useAuth } from '../../auth/AuthProvider';
import { Bell, ChevronDown, ChevronRight } from 'lucide-react';
import type { LucideIcon } from 'lucide-react';
import { Link } from 'react-router-dom';

interface BreadcrumbItem {
  label: string;
  to?: string;
}

interface HeaderProps {
  title: string;
  subtitle?: string;
  variant?: 'default' | 'users';
  pageIcon?: LucideIcon;
  titleBadge?: string;
  breadcrumbs?: BreadcrumbItem[];
  showNotificationIcon?: boolean;
  profileRole?: string;
  showProfileChevron?: boolean;
}

export function Header({
  title,
  subtitle,
  variant = 'default',
  pageIcon: PageIcon,
  titleBadge,
  breadcrumbs,
  showNotificationIcon = false,
  profileRole,
  showProfileChevron = false,
}: HeaderProps) {
  const { user } = useAuth();
  const titleContents = titleBadge ? (
    <>
      <span className="admin-header-title-text">{title}</span>
      <span className="admin-header-title-badge" aria-hidden="true">{titleBadge}</span>
    </>
  ) : title;

  return (
    <header className={`admin-header${variant === 'users' ? ' admin-header--users' : ''}`}>
      <div className="admin-header-left">
        {breadcrumbs && breadcrumbs.length > 0 && (
          <nav className="admin-header-breadcrumbs" aria-label="Breadcrumb">
            {breadcrumbs.map((item, index) => (
              <span className="admin-header-breadcrumb-item" key={`${item.label}-${index}`}>
                {index > 0 && <ChevronRight className="admin-header-breadcrumb-separator" aria-hidden="true" />}
                {item.to ? (
                  <Link to={item.to}>{item.label}</Link>
                ) : (
                  <span aria-current="page">{item.label}</span>
                )}
              </span>
            ))}
          </nav>
        )}
        {PageIcon ? (
          <div className="admin-header-heading admin-header-heading--icon">
            <span className="admin-header-page-icon">
              <PageIcon aria-hidden="true" />
            </span>
            <div className="admin-header-title-copy">
              <h1 className="admin-header-title">{titleContents}</h1>
              {subtitle && <p className="admin-header-subtitle">{subtitle}</p>}
            </div>
          </div>
        ) : (
          <>
            <h1 className="admin-header-title">{titleContents}</h1>
            {subtitle && <p className="admin-header-subtitle">{subtitle}</p>}
          </>
        )}
      </div>
      <div className="admin-header-right">
        {showNotificationIcon && (
          <span className="admin-header-notification" aria-hidden="true">
            <Bell />
          </span>
        )}
        <div className="admin-header-profile">
          <div className="admin-header-avatar">
            {user?.name?.charAt(0).toUpperCase() ?? 'A'}
          </div>
          {profileRole ? (
            <span className="admin-header-profile-copy">
              <span className="admin-header-name">{user?.name ?? 'Administrator'}</span>
              <span className="admin-header-role">{profileRole}</span>
            </span>
          ) : (
            <span className="admin-header-name">{user?.name ?? 'Administrator'}</span>
          )}
          {showProfileChevron && (
            <ChevronDown className="admin-header-profile-chevron" aria-hidden="true" />
          )}
        </div>
      </div>
    </header>
  );
}
