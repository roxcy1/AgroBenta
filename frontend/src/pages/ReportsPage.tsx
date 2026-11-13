import { Header } from '../features/admin/components/Header';
import { ReportsPage as ReportsFeature } from '../features/admin/reports/components/ReportsPage';
import { ChartNoAxesCombined } from 'lucide-react';
import './ReportsPage.css';

export default function ReportsPage() {
  return (
    <div className="reports-page-shell">
      <Header
        title="Reports"
        subtitle="View marketplace reports and analytics"
        pageIcon={ChartNoAxesCombined}
        profileRole="Administrator"
        showProfileChevron
      />
      <ReportsFeature />
    </div>
  );
}
