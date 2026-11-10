import { Header } from '../features/admin/components/Header';
import { SettingsPage as SettingsFeature } from '../features/admin/settings/components/SettingsPage';
import { Settings } from 'lucide-react';
import './SettingsPage.css';

export default function SettingsPage() {
  return (
    <div className="settings-page-shell">
      <Header
        title="Settings"
        subtitle="Manage platform settings"
        pageIcon={Settings}
        profileRole="Administrator"
        showProfileChevron
      />
      <SettingsFeature />
    </div>
  );
}
