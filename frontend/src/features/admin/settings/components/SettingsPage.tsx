import { useMemo, useState } from 'react';
import { useSettings, useUpdateSettings } from '../api/useSettings';
import type { Setting } from '../api/useSettings';

const GROUP_LABELS: Record<string, string> = {
  system: 'System',
  admin_contact: 'Admin Contact',
};

function buildDefaultValues(data: Record<string, Setting[]> | undefined): Record<string, string> {
  if (!data) return {};
  const values: Record<string, string> = {};
  for (const group of Object.values(data)) {
    for (const setting of group) {
      values[setting.key] = setting.value;
    }
  }
  return values;
}

export function SettingsPage() {
  const { data, isLoading, error, refetch } = useSettings();
  const updateMutation = useUpdateSettings();

  const [edits, setEdits] = useState<Record<string, string>>({});
  const [hasChanges, setHasChanges] = useState(false);
  const [saveMessage, setSaveMessage] = useState<string | null>(null);

  const defaultValues = useMemo(() => buildDefaultValues(data), [data]);

  const formValues = useMemo(() => ({ ...defaultValues, ...edits }), [defaultValues, edits]);

  const handleChange = (key: string, value: string) => {
    setEdits((prev) => ({ ...prev, [key]: value }));
    setHasChanges(true);
    setSaveMessage(null);
  };

  const handleSave = async () => {
    setSaveMessage(null);

    const changed: Record<string, string> = {};
    for (const key of Object.keys(formValues)) {
      if (formValues[key] !== defaultValues[key]) {
        changed[key] = formValues[key];
      }
    }

    if (Object.keys(changed).length === 0) {
      setHasChanges(false);
      return;
    }

    try {
      const result = await updateMutation.mutateAsync(changed);
      setHasChanges(false);
      setEdits({});
      if (result.rejected.length > 0) {
        setSaveMessage(`Updated ${result.updated.length} setting(s). ${result.rejected.length} key(s) were rejected.`);
      } else {
        setSaveMessage(`Updated ${result.updated.length} setting(s) successfully.`);
      }
    } catch {
      setSaveMessage('Failed to save settings. Please try again.');
    }
  };

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

  const groups = data ?? {};
  const groupKeys = Object.keys(groups).sort();

  return (
    <div className="settings-content">
      {saveMessage && (
        <div className={`settings-message ${saveMessage.includes('Failed') ? 'settings-message--error' : 'settings-message--success'}`}>
          {saveMessage}
        </div>
      )}

      {groupKeys.map((groupKey) => {
        const settings = groups[groupKey];
        return (
          <div key={groupKey} className="settings-group">
            <h2 className="settings-group-title">{GROUP_LABELS[groupKey] ?? groupKey}</h2>
            <div className="settings-group-fields">
              {settings.map((setting: Setting) => (
                <div key={setting.key} className="settings-field">
                  <label htmlFor={`setting-${setting.key}`} className="settings-label">
                    {setting.label}
                  </label>
                  {setting.description && (
                    <p className="settings-description">{setting.description}</p>
                  )}
                  {setting.key === 'system.description' ? (
                    <textarea
                      id={`setting-${setting.key}`}
                      className="settings-textarea"
                      value={formValues[setting.key] ?? ''}
                      onChange={(e) => handleChange(setting.key, e.target.value)}
                      rows={3}
                    />
                  ) : (
                    <input
                      id={`setting-${setting.key}`}
                      type={setting.key.includes('email') ? 'email' : 'text'}
                      className="settings-input"
                      value={formValues[setting.key] ?? ''}
                      onChange={(e) => handleChange(setting.key, e.target.value)}
                    />
                  )}
                </div>
              ))}
            </div>
          </div>
        );
      })}

      <div className="settings-actions">
        <button
          type="button"
          className="settings-save-button"
          disabled={!hasChanges || updateMutation.isPending}
          onClick={() => void handleSave()}
        >
          {updateMutation.isPending ? 'Saving...' : 'Save Changes'}
        </button>
      </div>
    </div>
  );
}
