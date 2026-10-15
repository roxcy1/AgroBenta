import { useMemo, useState } from 'react';
import { useSettings, useUpdateSettings } from '../api/useSettings';
import { buildSections, flattenFields } from '../settingsSchema';
import type { ResolvedSettingField } from '../settingsSchema';
import { initialSaveDialogState, nextSaveState, planSave } from '../settingsSave';
import type { SaveDialogState } from '../settingsSave';
import {
  settingsErrorMessage,
  settingsRejectedMessage,
  settingsSuccessMessage,
} from '../settingsErrorMessage';
import SettingsConfirmDialog from './SettingsConfirmDialog';
import { useToast } from '../../../../lib/toast/ToastProvider';

export function SettingsPage() {
  const { data, isLoading, error, refetch } = useSettings();
  const updateSettings = useUpdateSettings();
  const toast = useToast();

  const [edits, setEdits] = useState<Record<string, string>>({});
  const [touched, setTouched] = useState<Record<string, boolean>>({});
  const [attempted, setAttempted] = useState(false);
  const [dialog, setDialog] = useState<SaveDialogState>(initialSaveDialogState);

  const sections = useMemo(() => buildSections(data), [data]);
  const fields = useMemo(() => flattenFields(sections), [sections]);
  const plan = useMemo(() => planSave(fields, edits), [fields, edits]);

  if (isLoading) {
    return (
      <div className="settings-content">
        <div className="settings-loading">
          <div className="loading-spinner" />
          <span>Loading settings...</span>
        </div>
      </div>
    );
  }

  if (error) {
    return (
      <div className="settings-content">
        <div className="settings-error">
          <p className="settings-error-text">Failed to load settings.</p>
          <button type="button" className="settings-retry-button" onClick={() => void refetch()}>
            Retry
          </button>
        </div>
      </div>
    );
  }

  function handleEdit(key: string, value: string) {
    setEdits((current) => ({ ...current, [key]: value }));
  }

  function handleBlur(key: string) {
    setTouched((current) => ({ ...current, [key]: true }));
  }

  function showError(key: string): boolean {
    return attempted || touched[key] === true;
  }

  function handleSaveRequest() {
    setAttempted(true);

    if (!plan.canSave) {
      return;
    }

    const { state } = nextSaveState(dialog, 'request');
    setDialog(state);
  }

  function handleCancel() {
    const { state } = nextSaveState(dialog, 'cancel');
    setDialog(state);
  }

  function handleConfirm() {
    const { state, effect } = nextSaveState(dialog, 'submit');
    setDialog(state);

    if (effect !== 'save') {
      return;
    }

    updateSettings.mutate(plan.payload, {
      onSuccess: (result) => {
        if (result.rejected.length > 0) {
          toast.error(settingsRejectedMessage(result.rejected));
        } else {
          toast.success(settingsSuccessMessage(result.updated));
        }

        setEdits({});
        setTouched({});
        setAttempted(false);
        setDialog(initialSaveDialogState);
      },
      onError: (saveError) => {
        // Edits are deliberately left in place so the administrator can correct
        // and retry without retyping.
        toast.error(settingsErrorMessage(saveError));
        setDialog(initialSaveDialogState);
      },
    });
  }

  const isPending = dialog.pending || updateSettings.isPending;

  return (
    <div className="settings-content">
      {sections.map((section) => (
        <div key={section.id} className="settings-group">
          <h2 className="settings-group-title">{section.title}</h2>
          <div className="settings-group-fields">
            {section.fields.map((field) => (
              <SettingField
                key={field.key}
                field={field}
                value={edits[field.key] ?? field.value}
                error={showError(field.key) ? plan.errors[field.key] : undefined}
                disabled={isPending}
                onChange={(value) => handleEdit(field.key, value)}
                onBlur={() => handleBlur(field.key)}
              />
            ))}
          </div>
        </div>
      ))}

      <div className="settings-actions">
        <button
          type="button"
          className="settings-save-button"
          disabled={plan.changes.length === 0 || isPending}
          onClick={handleSaveRequest}
        >
          {updateSettings.isPending ? 'Saving…' : 'Save Changes'}
        </button>
      </div>

      {dialog.open && (
        <SettingsConfirmDialog
          changes={plan.changes}
          isPending={dialog.pending}
          onCancel={handleCancel}
          onConfirm={handleConfirm}
        />
      )}
    </div>
  );
}

interface SettingFieldProps {
  field: ResolvedSettingField;
  value: string;
  error: string | undefined;
  disabled: boolean;
  onChange: (value: string) => void;
  onBlur: () => void;
}

function SettingField({ field, value, error, disabled, onChange, onBlur }: SettingFieldProps) {
  const inputId = `setting-${field.key}`;
  const errorId = `${inputId}-error`;
  const describedBy = error !== undefined ? errorId : undefined;
  const showDefault = field.isDefault && value === field.default;

  const inputMode =
    field.type === 'integer' ? 'numeric' : field.type === 'decimal' ? 'decimal' : undefined;

  return (
    <div className="settings-field">
      <label className="settings-label" htmlFor={inputId}>
        {field.label}
      </label>
      {field.description && <p className="settings-description">{field.description}</p>}

      {field.multiline ? (
        <textarea
          id={inputId}
          className={`settings-textarea${error !== undefined ? ' settings-input--error' : ''}`}
          value={value}
          maxLength={field.maxLength}
          disabled={disabled}
          aria-invalid={error !== undefined}
          aria-describedby={describedBy}
          onChange={(event) => onChange(event.target.value)}
          onBlur={onBlur}
        />
      ) : (
        <input
          id={inputId}
          className={`settings-input${error !== undefined ? ' settings-input--error' : ''}`}
          type={field.type === 'email' ? 'email' : 'text'}
          inputMode={inputMode}
          value={value}
          maxLength={field.maxLength}
          disabled={disabled}
          aria-invalid={error !== undefined}
          aria-describedby={describedBy}
          onChange={(event) => onChange(event.target.value)}
          onBlur={onBlur}
        />
      )}

      {showDefault && <span className="settings-default-note">Showing the default value.</span>}
      {error !== undefined && (
        <p className="settings-field-error" id={errorId} role="alert">
          {error}
        </p>
      )}
    </div>
  );
}
