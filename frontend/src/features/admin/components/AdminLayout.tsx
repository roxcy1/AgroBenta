import { Outlet } from 'react-router-dom';
import { Sidebar } from './Sidebar';
import { useAdminRealtime } from '../api/useAdminRealtime';

export function AdminLayout() {
  // One real-time subscription for the whole admin area; it invalidates the
  // affected react-query caches when an audited action is broadcast.
  useAdminRealtime();

  return (
    <div className="admin-layout">
      <Sidebar />
      <main className="admin-main">
        <Outlet />
      </main>
    </div>
  );
}
