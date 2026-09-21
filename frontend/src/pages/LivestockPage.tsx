import { Header } from '../features/admin/components/Header';
import { ListingsTab } from '../features/admin/livestock/components/ListingsTab';

export default function LivestockPage() {
  return (
    <>
      <Header title="Livestock Listings" subtitle="Browse and manage livestock listings" />
      <div className="lv-content">
        <ListingsTab />
      </div>
    </>
  );
}
