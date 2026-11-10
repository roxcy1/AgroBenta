import { Header } from '../features/admin/components/Header';
import { ActivitiesPage as ActivitiesFeature } from '../features/admin/activities/components/ActivitiesPage';
import { Activity } from 'lucide-react';

export default function ActivitiesPage() {
  return (
    <>
      <Header
        title="Activities"
        subtitle="Monitor platform activity"
        pageIcon={Activity}
        profileRole="Administrator"
        showProfileChevron
      />
      <div className="lv-content">
        <ActivitiesFeature />
      </div>
    </>
  );
}
