import { useAuth } from '../../auth/AuthProvider';

interface HeaderProps {
  title: string;
  subtitle?: string;
}

export function Header({ title, subtitle }: HeaderProps) {
  const { user } = useAuth();

  return (
    <header className="admin-header">
      <div className="admin-header-left">
        <h1 className="admin-header-title">{title}</h1>
        {subtitle && <p className="admin-header-subtitle">{subtitle}</p>}
      </div>
      <div className="admin-header-right">
        <div className="admin-header-profile">
          <div className="admin-header-avatar">
            {user?.name?.charAt(0).toUpperCase() ?? 'A'}
          </div>
          <span className="admin-header-name">{user?.name ?? 'Administrator'}</span>
        </div>
      </div>
    </header>
  );
}
