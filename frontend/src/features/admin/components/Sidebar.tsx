import { NavLink } from 'react-router-dom';
import { useAuth } from '../../auth/AuthProvider';
import {
  Activity,
  BadgeCheck,
  Beef,
  ChartNoAxesCombined,
  LayoutDashboard,
  LogOut,
  ReceiptText,
  Settings,
  Users,
  Wheat,
  type LucideIcon,
} from 'lucide-react';

const NAV_ITEMS: { to: string; label: string; icon: LucideIcon }[] = [
  { to: '/', label: 'Dashboard', icon: LayoutDashboard },
  { to: '/users', label: 'Users', icon: Users },
  { to: '/livestock', label: 'Livestock', icon: Beef },
  { to: '/seller-verification', label: 'Seller Verification', icon: BadgeCheck },
  { to: '/transactions', label: 'Transactions', icon: ReceiptText },
  { to: '/activities', label: 'Activities', icon: Activity },
  { to: '/reports', label: 'Reports', icon: ChartNoAxesCombined },
  { to: '/settings', label: 'Settings', icon: Settings },
];

export function Sidebar() {
  const { logout } = useAuth();

  return (
    <aside className="sidebar">
      <div className="sidebar-logo">
        <Wheat className="sidebar-logo-icon" aria-hidden="true" />
        <span className="sidebar-logo-text">AgroBenta</span>
      </div>

      <nav className="sidebar-nav">
        {NAV_ITEMS.map((item) => {
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
            </NavLink>
          );
        })}
      </nav>

      <button type="button" className="sidebar-logout" onClick={() => void logout()}>
        <LogOut className="sidebar-nav-icon" aria-hidden="true" />
        <span className="sidebar-nav-label">Logout</span>
      </button>
    </aside>
  );
}