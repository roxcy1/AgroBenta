import { Header } from '../features/admin/components/Header';
import { ReportsPage as ReportsFeature } from '../features/admin/reports/components/ReportsPage';

export default function ReportsPage() {
  return (
    <>
      <Header title="Reports" subtitle="Data Analytics Overview" />
      <ReportsFeature />
    </>
  );
}
