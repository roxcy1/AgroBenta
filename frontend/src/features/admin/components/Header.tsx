import { useEffect, useRef, useState } from 'react';
import { useAuth } from '../../auth/AuthProvider';
import { Bell, ChevronDown, ChevronRight, LogOut, Settings } from 'lucide-react';
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
  /** Kept for existing page callers; the compact profile control omits this subtitle. */
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
  showProfileChevron = true,
}: HeaderProps) {
  const { user, logout } = useAuth();
  const [profileMenuOpen, setProfileMenuOpen] = useState(false);
  const profileMenuRef = useRef<HTMLDivElement>(null);
  const profileTriggerRef = useRef<HTMLButtonElement>(null);
  const profileName = user?.name ?? 'Administrator';

  useEffect(() => {
    if (!profileMenuOpen) return;

    const closeOnOutsideClick = (event: MouseEvent) => {
      if (!profileMenuRef.current?.contains(event.target as Node)) {
        setProfileMenuOpen(false);
      }
    };
    const closeOnEscape = (event: KeyboardEvent) => {
      if (event.key === 'Escape') {
        setProfileMenuOpen(false);
        profileTriggerRef.current?.focus();
      }
    };

    document.addEventListener('mousedown', closeOnOutsideClick);
    document.addEventListener('keydown', closeOnEscape);
    return () => {
      document.removeEventListener('mousedown', closeOnOutsideClick);
      document.removeEventListener('keydown', closeOnEscape);
    };
  }, [profileMenuOpen]);

  const handleLogout = () => {
    setProfileMenuOpen(false);
    void logout();
  };
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
        <div className="admin-header-profile-menu" ref={profileMenuRef}>
          <button
            type="button"
            className="admin-header-profile-trigger admin-header-profile"
            aria-label="Open administrator menu"
            aria-expanded={profileMenuOpen}
            aria-controls={profileMenuOpen ? 'admin-profile-menu' : undefined}
            onClick={() => setProfileMenuOpen((open) => !open)}
            ref={profileTriggerRef}
          >
            <span className="admin-header-avatar">
              {profileName.charAt(0).toUpperCase()}
            </span>
            <span className="admin-header-name">{profileName}</span>
            {showProfileChevron && (
              <ChevronDown className="admin-header-profile-chevron" aria-hidden="true" />
            )}
          </button>
          {profileMenuOpen && (
            <div className="admin-header-profile-dropdown" id="admin-profile-menu">
              <Link
                className="admin-header-profile-dropdown-item"
                to="/settings"
                onClick={() => setProfileMenuOpen(false)}
              >
                <Settings aria-hidden="true" />
                <span>Settings</span>
              </Link>
              <button
                type="button"
                className="admin-header-profile-dropdown-item admin-header-profile-dropdown-item--sign-out"
                onClick={handleLogout}
              >
                <LogOut aria-hidden="true" />
                <span>Sign Out</span>
              </button>
            </div>
          )}
        </div>
      </div>
    </header>
  );
}
