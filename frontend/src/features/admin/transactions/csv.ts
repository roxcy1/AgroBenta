import type { Transaction } from './api/useTransactions';
import { buildCsvContent } from '../../../lib/csv';

export { downloadCsv, escapeCsvField } from '../../../lib/csv';

const CSV_HEADERS = [
  'Transaction ID',
  'Buyer Name',
  'Buyer Email',
  'Seller Name',
  'Seller Email',
  'Livestock Type',
  'Breed',
  'Quantity',
  'Total Amount',
  'Status',
  'Created At',
];

export function buildTransactionsCsv(transactions: Transaction[]): string {
  return buildCsvContent([
    CSV_HEADERS,
    ...transactions.map((tx) => [
      tx.id,
      tx.buyer?.name ?? '',
      tx.buyer?.email ?? '',
      tx.seller?.name ?? '',
      tx.seller?.email ?? '',
      tx.listing?.livestock_type ?? '',
      tx.listing?.breed ?? '',
      tx.quantity,
      tx.total_amount,
      tx.status,
      tx.created_at,
    ]),
  ]);
}

function pad(value: number): string {
  return String(value).padStart(2, '0');
}

export function buildTransactionsFilename(now: Date = new Date()): string {
  const stamp = `${now.getFullYear()}${pad(now.getMonth() + 1)}${pad(now.getDate())}-${pad(now.getHours())}${pad(now.getMinutes())}${pad(now.getSeconds())}`;
  return `transactions-${stamp}.csv`;
}
