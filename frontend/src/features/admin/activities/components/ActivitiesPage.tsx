import { useState } from 'react';
import { useActivities } from '../api/useActivities';
import type { Activity } from '../api/useActivities';
import { useUsers } from '../../users/api/useUsers';
import ActivityDetailDialog from './ActivityDetailDialog';
import {
  ACTIVITY_ACTION_OPTIONS,
  activityActionLabel,
  activityActorLabel,
  activityChanges,
  activityTargetLabel,
  activityTimestampTitle,
  emptyActivitiesMessage,
  formatActivityTimestamp,
  hasActiveActivityFilters,
} from '../activityFormat';

export function ActivitiesPage() {
  const [search, setSearch] = useState('');
  const [searchInput, setSearchInput] = useState('');
  const [actionFilter, setActionFilter] = useState('');
  const [userFilter, setUserFilter] = useState('');
  const [dateFrom, setDateFrom] = useState('');
  const [dateTo, setDateTo] = useState('');
  const [appliedDates, setAppliedDates] = useState<{ date_from?: string; date_to?: string }>({});
  const [page, setPage] = useState(1);
  const [selectedActivity, setSelectedActivity] = useState<Activity | null>(null);

  const filters = {
    search: search || undefined,
    action: actionFilter || undefined,
    user_id: userFilter ? Number(userFilter) : undefined,
    date_from: appliedDates.date_from,
    date_to: appliedDates.date_to,
  };

  const { data, isLoading, isFetching, error, refetch } = useActivities({
    ...filters,
    page,
    per_page: 15,
  });

  const { data: usersData } = useUsers({ page: 1, per_page: 100 });

  const handleSearch = () => {    setSearch(searchInput);
    setPage(1);
  };

  const handleSearchKeyDown = (e: React.KeyboardEvent<HTMLInputElement>) => {
    if (e.key === 'Enter') {
      handleSearch();
    }
  };

  const handleActionChange = (value: string) => {
    setActionFilter(value);
    setPage(1);
  };

  const handleUserChange = (value: string) => {
    setUserFilter(value);
    setPage(1);
  };

  const handleApplyDates = () => {
    const next: { date_from?: string; date_to?: string } = {};
    if (dateFrom) next.date_from = dateFrom;
    if (dateTo) next.date_to = dateTo;
    setAppliedDates(next);
    setPage(1);
  };

  const handleClearDates = () => {
    setDateFrom('');
    setDateTo('');
    setAppliedDates({});
    setPage(1);
  };

  const handleClearFilters = () => {
    setSearch('');
    setSearchInput('');
    setActionFilter('');
    setUserFilter('');
    setDateFrom('');
    setDateTo('');
    setAppliedDates({});
    setPage(1);
  };

  const handlePageChange = (newPage: number) => {
    setPage(newPage);
  };

  const activities = data?.activities ?? [];
  const pagination = data?.pagination;
  const actors = usersData?.users ?? [];
  const filtersActive = hasActiveActivityFilters(filters);

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

          <div className="lv-filters">
            <select
              className="lv-filter-select"
              aria-label="Filter by action"
              value={actionFilter}
              onChange={(e) => handleActionChange(e.target.value)}
            >
              {ACTIVITY_ACTION_OPTIONS.map((option) => (
                <option key={option.value} value={option.value}>
                  {option.label}
                </option>
              ))}
            </select>

            <select
              className="lv-filter-select"
              aria-label="Filter by user"
              value={userFilter}
              onChange={(e) => handleUserChange(e.target.value)}
            >
              <option value="">All Users</option>
              {actors.map((user) => (
                <option key={user.id} value={String(user.id)}>
                  {user.name}
                </option>
              ))}
            </select>
          </div>

          {filtersActive && (
            <button
              type="button"
              className="reports-clear-button"
              onClick={handleClearFilters}
            >
              Clear Filters
            </button>
          )}
        </div>

        <div className="reports-filter-row">
          <div className="reports-filter-group">
            <label className="reports-filter-label" htmlFor="activities-date-from">
              From Date
            </label>
            <input
              id="activities-date-from"
              type="date"
              className="reports-filter-input"
              value={dateFrom}
              onChange={(e) => setDateFrom(e.target.value)}
            />
          </div>

          <div className="reports-filter-group">
            <label className="reports-filter-label" htmlFor="activities-date-to">
              To Date
            </label>
            <input
              id="activities-date-to"
              type="date"
              className="reports-filter-input"
              value={dateTo}
              onChange={(e) => setDateTo(e.target.value)}
            />
          </div>

          <div className="reports-filter-actions">
            <button type="button" className="lv-search-button" onClick={handleApplyDates}>
              Apply
            </button>
            {(dateFrom || dateTo) && (
              <button type="button" className="reports-clear-button" onClick={handleClearDates}>
                Clear
              </button>
            )}
          </div>
        </div>
      </div>

      {isFetching && !isLoading && (
        <p className="reports-updating">Updating activities…</p>
      )}

      {isLoading ? (
        <div className="lv-loading">
          <div className="loading-spinner" />
          <span>Loading activities...</span>
        </div>
      ) : error ? (
        <div className="lv-error">
          <p className="lv-error-text">Failed to load activities.</p>
          <button type="button" className="lv-retry-button" onClick={() => refetch()}>
            Retry
          </button>
        </div>
      ) : activities.length === 0 ? (
        <div className="lv-empty">
          <p>{emptyActivitiesMessage(hasActiveActivityFilters(filters))}</p>
        </div>
      ) : (
        <>
          <div className="lv-table-container">
            <table className="lv-table">
              <thead>
                <tr>
                  <th>Actor</th>
                  <th>Action</th>
                  <th>Target</th>
                  <th>Description</th>
                  <th>Changes</th>
                  <th>Date/Time</th>
                  <th>Details</th>
                </tr>
              </thead>
              <tbody>
                {activities.map((activity) => {
                  const changes = activityChanges(activity.metadata);

                  return (
                    <tr key={activity.id}>
                      <td className="lv-name-cell">{activityActorLabel(activity.user)}</td>
                      <td>{activityActionLabel(activity.action)}</td>
                      <td>{activityTargetLabel(activity.metadata)}</td>
                      <td>{activity.description ?? '\u2014'}</td>
                      <td className="activity-changes-cell">
                        {changes.length === 0 ? (
                          '\u2014'
                        ) : (
                          <ul className="activity-change-list">
                            {changes.map((change) => (
                              <li key={change.field}>
                                {change.label}: {change.from}
                                {' \u2192 '}
                                {change.to}
                              </li>
                            ))}
                          </ul>
                        )}
                      </td>
                      <td className="lv-date-cell">
                        <time
                          dateTime={activity.created_at}
                          title={activityTimestampTitle(activity.created_at)}
                        >
                          {formatActivityTimestamp(activity.created_at)}
                        </time>
                      </td>
                      <td>
                        <div className="lv-action-buttons">
                          <button
                            type="button"
                            className="lv-action-btn lv-action-btn--view"
                            onClick={() => setSelectedActivity(activity)}
                          >
                            View
                          </button>
                        </div>
                      </td>
                    </tr>
                  );
                })}
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

      {selectedActivity && (
        <ActivityDetailDialog
          activity={selectedActivity}
          onClose={() => setSelectedActivity(null)}
        />
      )}
    </div>
  );
}
