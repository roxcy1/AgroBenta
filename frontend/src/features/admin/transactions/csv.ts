import type { Transaction } from './api/useTransactions';

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

/**
 * Escapes a single CSV field per RFC 4180.
 *
 * A field is wrapped in double quotes when it contains a comma, a double quote,
 * or a line break; embedded double quotes are escaped by doubling them. Values
 * are stringified as-is, so an amount already formatted as a two-decimal string
 * is exported unchanged.
 */
export function escapeCsvField(value: string | number | null | undefined): string {
  const raw = value === null || value === undefined ? '' : String(value);
  if (/[",\r\n]/.test(raw)) {
    return `"${raw.replace(/"/g, '""')}"`;
  }
  return raw;
}

export function buildTransactionsCsv(transactions: Transaction[]): string {
  const lines: string[] = [];
  lines.push(CSV_HEADERS.map(escapeCsvField).join(','));

  for (const tx of transactions) {
    lines.push(
      [
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
      ]
        .map(escapeCsvField)
        .join(','),
    );
  }

  return lines.join('\r\n');
}

function pad(value: number): string {
  return String(value).padStart(2, '0');
}

export function buildTransactionsFilename(now: Date = new Date()): string {
  const stamp = `${now.getFullYear()}${pad(now.getMonth() + 1)}${pad(now.getDate())}-${pad(now.getHours())}${pad(now.getMinutes())}${pad(now.getSeconds())}`;
  return `transactions-${stamp}.csv`;
}

export function downloadCsv(filename: string, content: string): void {
  const blob = new Blob([content], { type: 'text/csv;charset=utf-8' });
  const url = URL.createObjectURL(blob);
  const link = document.createElement('a');
  link.href = url;
  link.download = filename;
  document.body.appendChild(link);
  link.click();
  document.body.removeChild(link);
  URL.revokeObjectURL(url);
}
