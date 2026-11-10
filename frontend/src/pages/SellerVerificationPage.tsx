import { Header } from '../features/admin/components/Header';
import { SellerVerificationTab } from '../features/admin/seller-verification/components/SellerVerificationTab';
import { ShieldCheck } from 'lucide-react';

export default function SellerVerificationPage() {
  return (
    <>
      <Header
        title="Verification"
        subtitle="Review seller verification requests"
        pageIcon={ShieldCheck}
        profileRole="Administrator"
        showProfileChevron
      />
      <div className="lv-content">
        <SellerVerificationTab />
      </div>
    </>
  );
}
