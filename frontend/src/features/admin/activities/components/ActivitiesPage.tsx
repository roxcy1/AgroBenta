import { useState } from 'react';
import { Link } from 'react-router-dom';
import { useActivities, useActivitySummary } from '../api/useActivities';
import type { Activity } from '../api/useActivities';
import { useUsers } from '../../users/api/useUsers';
import ActivityDetailDialog from './ActivityDetailDialog';
import {
  ACTIVITY_ACTION_OPTIONS,
  activityActionLabel,
  activityActorLabel,
  activityChanges,
  emptyActivitiesMessage,
  formatActivityTimestamp,
  getActivityTargetLink,
  hasActiveActivityFilters,
  activityTimestampTitle,
} from '../activityFormat';

export function ActivitiesPage() {
  const [search, setSearch] = useState('');
  const [searchInput, setSearchInput] = useState('');
  const [actionFilter, setActionFilter] = useState('');
  const [actionFilters, setActionFilters] = useState<string[]>([]);
  const [userFilter, setUserFilter] = useState('');
  const [dateFrom, setDateFrom] = useState('');
  const [dateTo, setDateTo] = useState('');
  const [appliedDates, setAppliedDates] = useState<{ date_from?: string; date_to?: string }>({});
  const [page, setPage] = useState(1);
  const [selectedActivity, setSelectedActivity] = useState<Activity | null>(null);

  const filters = {
    search: search || undefined,
    actions: actionFilters.length > 0 ? actionFilters : undefined,
    action: actionFilters.length > 0 ? undefined : (actionFilter || undefined),
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
  const { data: summaryData, isLoading: isSummaryLoading, error: summaryError } = useActivitySummary();

  const handleSearch = () => {
    setSearch(searchInput);
    setPage(1);
  };

  const handleSearchKeyDown = (e: React.KeyboardEvent<HTMLInputElement>) => {
    if (e.key === 'Enter') {
      handleSearch();
    }
  };

  const handleActionChange = (value: string) => {
    setActionFilter(value);
    setActionFilters([]);
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
    setActionFilters([]);
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
  const filtersActive = hasActiveActivityFilters({ 
    search: search || undefined,
    action: actionFilter || undefined,
    user_id: userFilter ? Number(userFilter) : undefined,
    date_from: appliedDates.date_from,
    date_to: appliedDates.date_to,
  }) || actionFilters.length > 0;

  const handleClearActionFilter = () => {
    setActionFilter('');
    setActionFilters([]);
    setPage(1);
  };

  const summary = summaryData;

  return (
    <div className="lv-tab-content">
      <div className="activity-summary-cards" role="region" aria-label="Activity summary last 24 hours">
        <article className="activity-summary-card" tabIndex={0} aria-label="Total activities in last 24 hours">
          <div className="activity-summary-card__header">
            <h3 className="activity-summary-card__title">Total Activities</h3>
            <span className="activity-summary-card__window">Last 24h</span>
          </div>
          <div className="activity-summary-card__body">
            {isSummaryLoading ? (
              <p className="activity-summary-card__value">Loading...</p>
            ) : summaryError ? (
              <p className="activity-summary-card__value activity-summary-card__value--muted">Unavailable</p>
            ) : (
              <p className="activity-summary-card__value">{summary?.total_activities ?? 0}</p>
            )}
          </div>
        </article>

        <article className="activity-summary-card" tabIndex={0} aria-label="Active actors in last 24 hours">
          <div className="activity-summary-card__header">
            <h3 className="activity-summary-card__title">Active Actors</h3>
            <span className="activity-summary-card__window">Last 24h</span>
          </div>
          <div className="activity-summary-card__body">
            {isSummaryLoading ? (
              <p className="activity-summary-card__value">Loading...</p>
            ) : summaryError ? (
              <p className="activity-summary-card__value activity-summary-card__value--muted">Unavailable</p>
            ) : (
              <p className="activity-summary-card__value">{summary?.active_actors ?? 0}</p>
            )}
          </div>
        </article>

        <article
          className="activity-summary-card activity-summary-card--emphasis"
          tabIndex={0}
          role="button"
          aria-pressed={actionFilters.length > 0 && actionFilters.every((a) => ['listing_approved', 'listing_rejected', 'listing_deactivated', 'seller_verification_approved', 'seller_verification_rejected'].includes(a))}
          aria-label="Moderation actions in last 24 hours"
          onClick={() => {
            const moderationActions = ['listing_approved', 'listing_rejected', 'listing_deactivated', 'seller_verification_approved', 'seller_verification_rejected'];
            const isActive = actionFilters.length === moderationActions.length && moderationActions.every((a) => actionFilters.includes(a));
            if (isActive) {
              setActionFilter('');
              setActionFilters([]);
              setPage(1);
            } else {
              setActionFilter('');
              setActionFilters(moderationActions);
              setPage(1);
            }
          }}
          onKeyDown={(e) => {
            if (e.key === 'Enter' || e.key === ' ') {
              e.preventDefault();
              const moderationActions = ['listing_approved', 'listing_rejected', 'listing_deactivated', 'seller_verification_approved', 'seller_verification_rejected'];
              const isActive = actionFilters.length === moderationActions.length && moderationActions.every((a) => actionFilters.includes(a));
              if (isActive) {
                setActionFilter('');
                setActionFilters([]);
                setPage(1);
              } else {
                setActionFilter('');
                setActionFilters(moderationActions);
                setPage(1);
              }
            }
          }}
        >
          <div className="activity-summary-card__header">
            <h3 className="activity-summary-card__title">Moderation Actions</h3>
            <span className="activity-summary-card__window">Last 24h</span>
          </div>
          <div className="activity-summary-card__body">
            {isSummaryLoading ? (
              <p className="activity-summary-card__value">Loading...</p>
            ) : summaryError ? (
              <p className="activity-summary-card__value activity-summary-card__value--muted">Unavailable</p>
            ) : (
              <p className="activity-summary-card__value">{summary?.moderation_actions ?? 0}</p>
            )}
          </div>
        </article>

        <article
          className="activity-summary-card"
          tabIndex={0}
          role="button"
          aria-pressed={actionFilter === 'settings_updated'}
          aria-label="Configuration changes in last 24 hours"
          onClick={() => {
            if (actionFilter === 'settings_updated') {
              handleClearActionFilter();
            } else {
              setActionFilter('settings_updated');
              setActionFilters([]);
              setPage(1);
            }
          }}
          onKeyDown={(e) => {
            if (e.key === 'Enter' || e.key === ' ') {
              e.preventDefault();
              if (actionFilter === 'settings_updated') {
                handleClearActionFilter();
              } else {
                setActionFilter('settings_updated');
                setActionFilters([]);
                setPage(1);
              }
            }
          }}
        >
          <div className="activity-summary-card__header">
            <h3 className="activity-summary-card__title">Configuration Changes</h3>
            <span className="activity-summary-card__window">Last 24h</span>
          </div>
          <div className="activity-summary-card__body">
            {isSummaryLoading ? (
              <p className="activity-summary-card__value">Loading...</p>
            ) : summaryError ? (
              <p className="activity-summary-card__value activity-summary-card__value--muted">Unavailable</p>
            ) : (
              <p className="activity-summary-card__value">{summary?.configuration_changes ?? 0}</p>
            )}
          </div>
        </article>
      </div>

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
                  const targetLink = getActivityTargetLink(activity.metadata);
                  const actorLabel = activityActorLabel(activity.user);

                  return (
                    <tr key={activity.id}>
                      <td className="lv-name-cell">
                        {activity.user ? (
                          <Link className="activity-link" to={`/users?user=${activity.user.id}`}>
                            {actorLabel}
                          </Link>
                        ) : (
                          actorLabel
                        )}
                      </td>
                      <td>{activityActionLabel(activity.action)}</td>
                      <td>
                        {targetLink.href ? (
                          <Link className="activity-link" to={targetLink.href}>
                            {targetLink.label}
                          </Link>
                        ) : (
                          targetLink.label
                        )}
                      </td>
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
