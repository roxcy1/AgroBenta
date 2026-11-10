import { useEffect, useState } from 'react';
import type { FormEvent } from 'react';
import type { AxiosError } from 'axios';
import { useToast } from '../../../../lib/toast/ToastProvider';
import { useUpdateAdminUser, type AdminUser } from '../api/useUsers';
import {
  apiUserErrorMessage,
  serverUserErrors,
  validateUserForm,
} from '../userValidation';
import type { UserFormErrors } from '../userValidation';

interface EditUserDialogProps {
  user: AdminUser;
  onClose: () => void;
}

export default function EditUserDialog({ user, onClose }: EditUserDialogProps) {
  const updateUser = useUpdateAdminUser();
  const toast = useToast();
  const [name, setName] = useState(user.name);
  const [email, setEmail] = useState(user.email);
  const [errors, setErrors] = useState<UserFormErrors>({});
  const [formError, setFormError] = useState<string>();

  useEffect(() => {
    function handleKeyDown(event: KeyboardEvent) {
      if (event.key === 'Escape' && !updateUser.isPending) onClose();
    }

    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, [onClose, updateUser.isPending]);

  function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setFormError(undefined);

    const trimmedName = name.trim();
    const trimmedEmail = email.trim();
    const validationErrors = validateUserForm(trimmedName, trimmedEmail);
    setErrors(validationErrors);
    if (Object.keys(validationErrors).length > 0) return;

    updateUser.mutate(
      { id: user.id, name: trimmedName, email: trimmedEmail },
      {
        onSuccess: () => {
          toast.success('User updated successfully.');
          onClose();
        },
        onError: (error) => {
          const fieldErrors = serverUserErrors(error);
          if (fieldErrors.name || fieldErrors.email) {
            setErrors(fieldErrors);
            return;
          }

          const status = (error as AxiosError)?.response?.status;
          const message = apiUserErrorMessage(error, 'Unable to update this user. Please try again.');
          if (status === 422) {
            setFormError(message);
          } else {
            toast.error(message);
          }
        },
      },
    );
  }

  function closeIfIdle() {
    if (!updateUser.isPending) onClose();
  }

  return (
    <div className="lv-action-modal-overlay" onClick={closeIfIdle}>
      <section
        className="lv-action-modal users-user-dialog"
        role="dialog"
        aria-modal="true"
        aria-labelledby="edit-user-title"
        onClick={(event) => event.stopPropagation()}
      >
        <h2 className="lv-action-modal-title" id="edit-user-title">Edit User</h2>
        <p className="lv-action-modal-desc">
          Update the user’s name and email address. Account permissions remain unchanged.
        </p>

        <form onSubmit={handleSubmit} noValidate>
          <div className="users-user-dialog-field">
            <label className="lv-action-modal-label" htmlFor="edit-user-name">
              Full Name
            </label>
            <input
              id="edit-user-name"
              className={`users-user-dialog-input${errors.name ? ' users-user-dialog-input--error' : ''}`}
              type="text"
              autoComplete="name"
              maxLength={255}
              value={name}
              disabled={updateUser.isPending}
              aria-invalid={errors.name !== undefined}
              aria-describedby={errors.name ? 'edit-user-name-error' : undefined}
              onChange={(event) => {
                setName(event.target.value);
                setErrors((current) => ({ ...current, name: undefined }));
                setFormError(undefined);
              }}
            />
            {errors.name && (
              <p className="users-user-dialog-error" id="edit-user-name-error" role="alert">
                {errors.name}
              </p>
            )}
          </div>

          <div className="users-user-dialog-field">
            <label className="lv-action-modal-label" htmlFor="edit-user-email">
              Email Address
            </label>
            <input
              id="edit-user-email"
              className={`users-user-dialog-input${errors.email ? ' users-user-dialog-input--error' : ''}`}
              type="email"
              autoComplete="email"
              maxLength={255}
              value={email}
              disabled={updateUser.isPending}
              aria-invalid={errors.email !== undefined}
              aria-describedby={errors.email ? 'edit-user-email-error' : undefined}
              onChange={(event) => {
                setEmail(event.target.value);
                setErrors((current) => ({ ...current, email: undefined }));
                setFormError(undefined);
              }}
            />
            {errors.email && (
              <p className="users-user-dialog-error" id="edit-user-email-error" role="alert">
                {errors.email}
              </p>
            )}
          </div>

          {formError && <p className="users-user-dialog-error" role="alert">{formError}</p>}

          <div className="lv-action-modal-buttons users-user-dialog-buttons">
            <button
              type="button"
              className="lv-action-cancel"
              disabled={updateUser.isPending}
              onClick={onClose}
            >
              Cancel
            </button>
            <button
              type="submit"
              className="lv-action-confirm lv-action-confirm--approve"
              disabled={updateUser.isPending}
            >
              {updateUser.isPending ? 'Saving…' : 'Save Changes'}
            </button>
          </div>
        </form>
      </section>
    </div>
  );
}
