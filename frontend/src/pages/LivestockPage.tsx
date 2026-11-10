import { Header } from '../features/admin/components/Header';
import { ListingsTab } from '../features/admin/livestock/components/ListingsTab';
import { Beef } from 'lucide-react';

export default function LivestockPage() {
  return (
    <>
      <Header
        title="Listings"
        subtitle="Manage livestock listings"
        pageIcon={Beef}
        profileRole="Administrator"
        showProfileChevron
      />
      <div className="lv-content">
        <ListingsTab />
      </div>
    </>
  );
}
