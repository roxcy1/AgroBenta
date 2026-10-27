import { useAuth } from '../../auth/AuthProvider';

export function TopNavBar() {
  const { user } = useAuth();

  return (
    <div className="top-nav">
      <div className="top-nav-inner">
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
