import { Header } from '../features/admin/components/Header';
import { TransactionsPage as TransactionsFeature } from '../features/admin/transactions/components/TransactionsPage';

export default function TransactionsPage() {
  return (
    <>
      <Header title="Transactions" subtitle="View and manage marketplace transactions" />
      <div className="lv-content">
        <TransactionsFeature />
      </div>
    </>
  );
}
