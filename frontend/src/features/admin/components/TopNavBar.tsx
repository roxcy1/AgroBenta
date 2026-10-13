import { Search } from 'lucide-react';
import { useAuth } from '../../auth/AuthProvider';

interface TopNavBarProps {
  search: string;
  onSearchChange: (value: string) => void;
}

export function TopNavBar({ search, onSearchChange }: TopNavBarProps) {
  const { user } = useAuth();

  return (
    <div className="top-nav">
      <div className="top-nav-inner">
        <label className="top-nav-search">
          <Search className="top-nav-search-icon" aria-hidden="true" />
          <input
            type="search"
            className="top-nav-search-input"
            placeholder="Search listings, users, transactions..."
            value={search}
            onChange={(event) => onSearchChange(event.target.value)}
            aria-label="Search"
          />
        </label>
        <div className="top-nav-profile">
          <div className="top-nav-profile-avatar">
            {user?.name?.charAt(0).toUpperCase() ?? 'A'}
          </div>
          <span className="top-nav-profile-name">{user?.name ?? 'Administrator'}</span>
        </div>
      </div>
    </div>
  );
}
