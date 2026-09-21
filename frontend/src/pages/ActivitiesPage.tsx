import { Header } from '../features/admin/components/Header';
import { ActivitiesPage as ActivitiesFeature } from '../features/admin/activities/components/ActivitiesPage';

export default function ActivitiesPage() {
  return (
    <>
      <Header title="Activities" subtitle="View platform activity logs" />
      <div className="lv-content">
        <ActivitiesFeature />
      </div>
    </>
  );
}
