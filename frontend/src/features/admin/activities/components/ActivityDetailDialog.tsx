import { useEffect } from 'react';
import { Link } from 'react-router-dom';
import { Activity as ActivityIcon, CalendarDays, ClipboardList, History } from 'lucide-react';
import type { Activity } from '../api/useActivities';
import { AdminDetailModalHeader } from '../../components/AdminDetailModalHeader';
import {
  activityActionLabel,
  activityActorLabel,
  activityChanges,
  activityContextEntries,
  activityTargetLabel,
  activityTimestampTitle,
  formatActivityTimestamp,
  getActivityTargetLink,
} from '../activityFormat';

interface ActivityDetailDialogProps {
  activity: Activity;
  onClose: () => void;
}

export default function ActivityDetailDialog({ activity, onClose }: ActivityDetailDialogProps) {
  useEffect(() => {
    function onKeyDown(event: KeyboardEvent) {
      if (event.key === 'Escape') onClose();
    }
    window.addEventListener('keydown', onKeyDown);
    return () => window.removeEventListener('keydown', onKeyDown);
  }, [onClose]);

  const changes = activityChanges(activity.metadata);
  const context = activityContextEntries(activity.metadata);
  const target = activityTargetLabel(activity.metadata);
  const targetLink = getActivityTargetLink(activity.metadata);

  return (
    <div className="lv-action-modal-overlay listing-details-overlay" onClick={onClose}>
      <div
        className="lv-action-modal lv-action-modal--detail lv-action-modal--listing-details"
        role="dialog"
        aria-modal="true"
        aria-labelledby="activity-details-title"
        onClick={(event) => event.stopPropagation()}
      >
        <AdminDetailModalHeader
          title={`Activity #${activity.id}`}
          subtitle={activity.description ?? activityActionLabel(activity.action)}
          titleId="activity-details-title"
          closeLabel="Close activity details"
          onClose={onClose}
        />

        <div className="lv-detail-body">
          <div className="lv-detail-grid">
            <section className="lv-detail-section">
              <h3 className="lv-detail-section-title">
                <ActivityIcon aria-hidden="true" />
                Summary
              </h3>
              <dl className="lv-detail-list">
                <div className="lv-detail-item">
                  <dt className="lv-detail-label">Actor</dt>
                  <dd className="lv-detail-value">{activityActorLabel(activity.user)}</dd>
                </div>
                {activity.user && (
                  <div className="lv-detail-item">
                    <dt className="lv-detail-label">Email</dt>
                    <dd className="lv-detail-value">{activity.user.email}</dd>
                  </div>
                )}
                <div className="lv-detail-item">
                  <dt className="lv-detail-label">Action</dt>
                  <dd className="lv-detail-value">{activityActionLabel(activity.action)}</dd>
                </div>
                <div className="lv-detail-item">
                  <dt className="lv-detail-label">Target</dt>
                  <dd className="lv-detail-value">
                    {targetLink.href ? (
                      <Link to={targetLink.href} className="activity-link">
                        {targetLink.label}
                      </Link>
                    ) : (
                      target
                    )}
                  </dd>
                </div>
                <div className="lv-detail-item">
                  <dt className="lv-detail-label">When</dt>
                  <dd className="lv-detail-value">
                    <time
                      dateTime={activity.created_at}
                      title={activityTimestampTitle(activity.created_at)}
                    >
                      {formatActivityTimestamp(activity.created_at)}
                    </time>
                  </dd>
                </div>
              </dl>
            </section>

            <section className="lv-detail-section">
              <h3 className="lv-detail-section-title">
                <History aria-hidden="true" />
                Changes
              </h3>
              {changes.length === 0 ? (
                <p className="lv-detail-value activity-muted">
                  No field changes were recorded for this activity.
                </p>
              ) : (
                <dl className="lv-detail-list">
                  {changes.map((change) => (
                    <div className="lv-detail-item" key={change.field}>
                      <dt className="lv-detail-label">{change.label}</dt>
                      <dd className="lv-detail-value">
                        <span className="activity-change-from">{change.from}</span>
                        <span className="activity-change-arrow" aria-hidden="true">
                          {' \u2192 '}
                        </span>
                        <span className="activity-change-to">{change.to}</span>
                      </dd>
                    </div>
                  ))}
                </dl>
              )}
            </section>

            <section className="lv-detail-section lv-detail-section--wide">
              <h3 className="lv-detail-section-title">
                <ClipboardList aria-hidden="true" />
                Context
              </h3>
              {context.length === 0 ? (
                <p className="lv-detail-value">No additional context recorded for this activity.</p>
              ) : (
                <dl className="lv-detail-list">
                  {context.map((entry) => (
                    <div className="lv-detail-item" key={entry.field}>
                      <dt className="lv-detail-label">{entry.label}</dt>
                      <dd className="lv-detail-value">{entry.value}</dd>
                    </div>
                  ))}
                </dl>
              )}
            </section>

            <section className="lv-detail-section lv-detail-section--wide">
              <h3 className="lv-detail-section-title">
                <CalendarDays aria-hidden="true" />
                Recorded
              </h3>
              <dl className="lv-detail-list">
                <div className="lv-detail-item">
                  <dt className="lv-detail-label">Occurred</dt>
                  <dd className="lv-detail-value">
                    <time
                      dateTime={activity.created_at}
                      title={activityTimestampTitle(activity.created_at)}
                    >
                      {formatActivityTimestamp(activity.created_at)}
                    </time>
                  </dd>
                </div>
                <div className="lv-detail-item">
                  <dt className="lv-detail-label">Target reference</dt>
                  <dd className="lv-detail-value">
                    {targetLink.href ? (
                      <Link to={targetLink.href} className="activity-link">
                        {targetLink.label}
                      </Link>
                    ) : (
                      target
                    )}
                  </dd>
                </div>
              </dl>
            </section>
          </div>
        </div>

        <footer className="lv-detail-footer listing-details-footer">
          <button type="button" className="listing-details-footer-close" onClick={onClose}>
            Close
          </button>
        </footer>
      </div>
    </div>
  );
}
