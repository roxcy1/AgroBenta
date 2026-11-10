import { Header } from '../features/admin/components/Header';
import { TransactionsPage as TransactionsFeature } from '../features/admin/transactions/components/TransactionsPage';
import { ArrowLeftRight } from 'lucide-react';

export default function TransactionsPage() {
  return (
    <>
      <Header
        title="Transactions"
        subtitle="Monitor marketplace transactions"
        pageIcon={ArrowLeftRight}
        profileRole="Administrator"
        showProfileChevron
      />
      <div className="lv-content">
        <TransactionsFeature />
      </div>
    </>
  );
}
