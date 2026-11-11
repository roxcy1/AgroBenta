import { NavLink } from 'react-router-dom';
import {
  Activity,
  BadgeCheck,
  Beef,
  ChartNoAxesCombined,
  LayoutDashboard,
  ReceiptText,
  Settings,
  Users,
  type LucideIcon,
} from 'lucide-react';
import { useSellerVerifications } from '../seller-verification/api/useSellerVerifications';
import './Sidebar.css';

const NAV_GROUPS: { label: string; items: { to: string; label: string; icon: LucideIcon }[] }[] = [
  {
    label: 'Overview',
    items: [{ to: '/', label: 'Dashboard', icon: LayoutDashboard }],
  },
  {
    label: 'Marketplace',
    items: [{ to: '/livestock', label: 'Livestock', icon: Beef }],
  },
  {
    label: 'Management',
    items: [
      { to: '/users', label: 'Users', icon: Users },
      { to: '/seller-verification', label: 'Seller Verification', icon: BadgeCheck },
      { to: '/transactions', label: 'Transactions', icon: ReceiptText },
      { to: '/activities', label: 'Activities', icon: Activity },
      { to: '/reports', label: 'Reports', icon: ChartNoAxesCombined },
    ],
  },
  {
    label: 'System',
    items: [
      { to: '/settings', label: 'Settings', icon: Settings },
    ],
  },
];

export function Sidebar() {
  const { data: pendingVerifications } = useSellerVerifications({
    status: 'pending_review',
    per_page: 1,
  });
  const pendingReviewCount = pendingVerifications?.pagination.total ?? 0;

  return (
    <aside className="sidebar">
      <div className="sidebar-logo">
        <img
          className="sidebar-logo-image"
          src="/images/agrobenta-sidebar-logo.png.png"
          alt="AgroBenta Livestock Marketplace"
        />
      </div>

      <nav className="sidebar-nav" aria-label="Administrator navigation">
        {NAV_GROUPS.map((group) => (
          <div className="sidebar-nav-group" key={group.label}>
            <p className="sidebar-nav-group-title">{group.label}</p>
            {group.items.map((item) => {
              const Icon = item.icon;
              return (
                <NavLink
                  key={item.to}
                  to={item.to}
                  end={item.to === '/'}
                  className={({ isActive }) =>
                    `sidebar-nav-item ${isActive ? 'sidebar-nav-item--active' : ''}`
                  }
                >
                  <Icon className="sidebar-nav-icon" aria-hidden="true" />
                  <span className="sidebar-nav-label">{item.label}</span>
                  {item.to === '/seller-verification' && pendingReviewCount > 0 && (
                    <span
                      className="sidebar-nav-badge"
                      aria-label={`${pendingReviewCount} pending verification requests`}
                    >
                      {pendingReviewCount}
                    </span>
                  )}
                </NavLink>
              );
            })}
          </div>
        ))}
      </nav>

    </aside>
  );
}
