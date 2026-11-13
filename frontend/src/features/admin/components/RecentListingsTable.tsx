import type { DashboardRecentListing } from '../api/useDashboard';
import { formatCurrency, formatDate } from './dashboardFormat';
import { StatusBadge } from './StatusBadge';
import { livestockTypeLabel, useLivestockTypes } from '../livestock/api/useLivestockTypes';

interface RecentListingsTableProps {
  listings: DashboardRecentListing[];
}

export function RecentListingsTable({ listings }: RecentListingsTableProps) {
  const { data: livestockTypes } = useLivestockTypes();
  if (listings.length === 0) {
    return (
      <div className="dashboard-empty-state">
        <p>No livestock listings available yet.</p>
      </div>
    );
  }

  return (
    <div className="dashboard-table-container">
      <table className="dashboard-table">
        <thead>
          <tr>
            <th>Livestock Type</th>
            <th>Breed</th>
            <th>Price</th>
            <th>Status</th>
            <th>Seller</th>
            <th>Date Added</th>
          </tr>
        </thead>
        <tbody>
          {listings.map((listing) => (
            <tr key={listing.id}>
              <td className="lv-name-cell">{livestockTypeLabel(listing.livestock_type, livestockTypes)}</td>
              <td>{listing.breed ?? '—'}</td>
              <td className="lv-price-cell">{formatCurrency(listing.asking_price)}</td>
              <td>
                <StatusBadge status={listing.status} />
              </td>
              <td className="lv-seller-cell">{listing.seller?.name ?? '—'}</td>
              <td className="lv-date-cell">{formatDate(listing.created_at)}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
