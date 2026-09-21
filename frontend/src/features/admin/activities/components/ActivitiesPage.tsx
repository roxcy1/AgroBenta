import { useState } from 'react';
import { useActivities } from '../api/useActivities';

function formatDateTime(dateString: string): string {
  const date = new Date(dateString);
  return date.toLocaleDateString('en-PH', {
    year: 'numeric',
    month: 'short',
    day: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
  });
}

export function ActivitiesPage() {
  const [search, setSearch] = useState('');
  const [page, setPage] = useState(1);
  const [searchInput, setSearchInput] = useState('');

  const { data, isLoading, error, refetch } = useActivities({
    search: search || undefined,
    page,
    per_page: 15,
  });

  const handleSearch = () => {
    setSearch(searchInput);
    setPage(1);
  };

  const handleSearchKeyDown = (e: React.KeyboardEvent<HTMLInputElement>) => {
    if (e.key === 'Enter') {
      handleSearch();
    }
  };

  const handlePageChange = (newPage: number) => {
    setPage(newPage);
  };

  if (isLoading) {
    return (
      <div className="lv-loading">
        <div className="loading-spinner" />
        <span>Loading activities...</span>
      </div>
    );
  }

  if (error) {
    return (
      <div className="lv-error">
        <p className="lv-error-text">Failed to load activities.</p>
        <button type="button" className="lv-retry-button" onClick={() => refetch()}>
          Retry
        </button>
      </div>
    );
  }

  const activities = data?.activities ?? [];
  const pagination = data?.pagination;

  return (
    <div className="lv-tab-content">
      <div className="lv-controls">
        <div className="lv-search-row">
          <div className="lv-search-wrapper">
            <input
              type="text"
              className="lv-search-input"
              placeholder="Search by action, description, or user..."
              value={searchInput}
              onChange={(e) => setSearchInput(e.target.value)}
              onKeyDown={handleSearchKeyDown}
            />
            <button type="button" className="lv-search-button" onClick={handleSearch}>
              Search
            </button>
          </div>
        </div>
      </div>

      {activities.length === 0 ? (
        <div className="lv-empty">
          <p>No activities found.</p>
        </div>
      ) : (
        <>
          <div className="lv-table-container">
            <table className="lv-table">
              <thead>
                <tr>
                  <th>User</th>
                  <th>Action</th>
                  <th>Description</th>
                  <th>Date/Time</th>
                </tr>
              </thead>
              <tbody>
                {activities.map((activity) => (
                  <tr key={activity.id}>
                    <td className="lv-name-cell">
                      {activity.user ? activity.user.name : 'System'}
                    </td>
                    <td>
                      <span className="lv-badge lv-badge--active">
                        {activity.action}
                      </span>
                    </td>
                    <td>{activity.description ?? '\u2014'}</td>
                    <td className="lv-date-cell">{formatDateTime(activity.created_at)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>

          {pagination && pagination.last_page > 1 && (
            <div className="lv-pagination">
              <button
                type="button"
                className="lv-page-button"
                disabled={pagination.current_page <= 1}
                onClick={() => handlePageChange(pagination.current_page - 1)}
              >
                Previous
              </button>
              <span className="lv-page-info">
                Page {pagination.current_page} of {pagination.last_page}
                {' '}
                <span className="lv-page-total">({pagination.total} activities)</span>
              </span>
              <button
                type="button"
                className="lv-page-button"
                disabled={pagination.current_page >= pagination.last_page}
                onClick={() => handlePageChange(pagination.current_page + 1)}
              >
                Next
              </button>
            </div>
          )}
        </>
      )}
    </div>
  );
}
