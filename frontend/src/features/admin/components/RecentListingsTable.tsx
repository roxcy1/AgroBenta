import type { DashboardRecentListing } from '../api/useDashboard';
import { statusLabel } from '../livestock/components/listingModeration';
import { formatCurrency, formatDate } from './dashboardFormat';

interface RecentListingsTableProps {
  listings: DashboardRecentListing[];
  filter?: string;
}

function matchesFilter(listing: DashboardRecentListing, filter: string): boolean {
  const query = filter.trim().toLowerCase();
  if (!query) return true;
  return (
    listing.livestock_type.toLowerCase().includes(query) ||
    (listing.breed ?? '').toLowerCase().includes(query) ||
    (listing.seller?.name ?? '').toLowerCase().includes(query)
  );
}

export function RecentListingsTable({ listings, filter = '' }: RecentListingsTableProps) {
  const visible = listings.filter((listing) => matchesFilter(listing, filter));

  if (visible.length === 0) {
    return (
      <div className="dashboard-empty-state">
        <p>{filter ? 'No listings match your search.' : 'No livestock listings available yet.'}</p>
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
          {visible.map((listing) => (
            <tr key={listing.id}>
              <td className="lv-name-cell">{listing.livestock_type}</td>
              <td>{listing.breed ?? '—'}</td>
              <td className="lv-price-cell">{formatCurrency(listing.asking_price)}</td>
              <td>
                <span className={`lv-badge lv-badge--${listing.status}`}>
                  {statusLabel(listing.status)}
                </span>
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
