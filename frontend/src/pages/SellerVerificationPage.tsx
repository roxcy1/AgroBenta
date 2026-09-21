import { Header } from '../features/admin/components/Header';
import { SellerVerificationTab } from '../features/admin/seller-verification/components/SellerVerificationTab';

export default function SellerVerificationPage() {
  return (
    <>
      <Header title="Seller Verification" subtitle="Review and manage seller verification requests" />
      <div className="lv-content">
        <SellerVerificationTab />
      </div>
    </>
  );
}
