import { useEffect } from 'react';
import type { SettingChange } from '../settingsChanges';
import { formatChangeValue } from '../settingsChanges';

interface SettingsConfirmDialogProps {
  changes: SettingChange[];
  isPending: boolean;
  onCancel: () => void;
  onConfirm: () => void;
}

/**
 * The last step before a settings update is sent.
 *
 * It lists exactly what will change — each setting with its current and new
 * value — so the update is confirmed against the diff rather than against the
 * whole form. Canceling closes the dialog without a request; confirming is the
 * only path that issues the `PUT`, and it is blocked while one is in flight.
 */
export default function SettingsConfirmDialog({
  changes,
  isPending,
  onCancel,
  onConfirm,
}: SettingsConfirmDialogProps) {
  useEffect(() => {
    function onKeyDown(event: KeyboardEvent) {
      if (event.key === 'Escape' && !isPending) onCancel();
    }
    window.addEventListener('keydown', onKeyDown);
    return () => window.removeEventListener('keydown', onKeyDown);
  }, [onCancel, isPending]);

  const count = changes.length;

  return (
    <div
      className="lv-action-modal-overlay"
      onClick={() => {
        if (!isPending) onCancel();
      }}
    >
      <div
        className="lv-action-modal"
        role="dialog"
        aria-modal="true"
        aria-labelledby="settings-confirm-title"
        onClick={(event) => event.stopPropagation()}
      >
        <h2 className="lv-action-modal-title" id="settings-confirm-title">
          Save changes?
        </h2>
        <p className="lv-action-modal-desc">
          {count === 1
            ? 'The following setting will be updated.'
            : `The following ${count} settings will be updated.`}
        </p>

        <div className="lv-table-container">
          <table className="lv-table">
            <thead>
              <tr>
                <th>Setting</th>
                <th>Current</th>
                <th>New</th>
              </tr>
            </thead>
            <tbody>
              {changes.map((change) => (
                <tr key={change.key}>
                  <td className="lv-name-cell">{change.label}</td>
                  <td>{formatChangeValue(change.oldValue)}</td>
                  <td>{formatChangeValue(change.newValue)}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>

        <div className="lv-action-modal-buttons settings-confirm-buttons">
          <button
            type="button"
            className="lv-action-cancel"
            disabled={isPending}
            onClick={onCancel}
          >
            Cancel
          </button>
          <button
            type="button"
            className="lv-action-confirm lv-action-confirm--approve"
            disabled={isPending}
            onClick={onConfirm}
          >
            {isPending ? 'Saving…' : 'Save'}
          </button>
        </div>
      </div>
    </div>
  );
}
