import { Header } from '../features/admin/components/Header';
import { SettingsPage as SettingsFeature } from '../features/admin/settings/components/SettingsPage';

export default function SettingsPage() {
  return (
    <>
      <Header title="Settings" subtitle="System configuration" />
      <SettingsFeature />
    </>
  );
}
