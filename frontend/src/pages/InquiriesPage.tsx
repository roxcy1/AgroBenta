import { Header } from '../features/admin/components/Header';
import { InquiriesPage as InquiriesFeature } from '../features/admin/inquiries/components/InquiriesPage';

export default function InquiriesPage() {
  return (
    <>
      <Header title="Inquiries" subtitle="Review buyer inquiries and manage their response status" />
      <div className="lv-content">
        <InquiriesFeature />
      </div>
    </>
  );
}
