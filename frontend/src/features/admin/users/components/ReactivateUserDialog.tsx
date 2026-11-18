import { useEffect, useState } from 'react';
import { useToast } from '../../../../lib/toast/ToastProvider';
import { useReactivateAdminUser, type AdminUser } from '../api/useUsers';
import { apiUserErrorMessage } from '../userValidation';

interface ReactivateUserDialogProps {
  user: AdminUser;
  onClose: () => void;
  onReactivated: () => void;
}

export default function ReactivateUserDialog({
  user,
  onClose,
  onReactivated,
}: ReactivateUserDialogProps) {
  const reactivateUser = useReactivateAdminUser();
  const toast = useToast();
  const [reason, setReason] = useState('');
  const trimmedReason = reason.trim();
  const reasonIsValid = trimmedReason.length >= 5;

  useEffect(() => {
    function handleKeyDown(event: KeyboardEvent) {
      if (event.key === 'Escape' && !reactivateUser.isPending) onClose();
    }

    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, [onClose, reactivateUser.isPending]);

  function handleReactivate() {
    if (!reasonIsValid) return;

    reactivateUser.mutate(
      { id: user.id, reason: trimmedReason },
      {
        onSuccess: () => {
          toast.success('User account reactivated.');
          onReactivated();
          onClose();
        },
        onError: (error) => {
          const message = apiUserErrorMessage(
            error,
            'Unable to reactivate this user. Please try again.',
          );
          toast.error(message);
        },
      },
    );
  }

  function closeIfIdle() {
    if (!reactivateUser.isPending) onClose();
  }

  return (
    <div className="lv-action-modal-overlay" onClick={closeIfIdle}>
      <section
        className="lv-action-modal users-user-dialog"
        role="alertdialog"
        aria-modal="true"
        aria-labelledby="reactivate-user-title"
        aria-describedby="reactivate-user-warning"
        onClick={(event) => event.stopPropagation()}
      >
        <h2 className="lv-action-modal-title" id="reactivate-user-title">Reactivate Account</h2>
        <p className="users-delete-user-identity">{user.name}</p>
        <p className="users-delete-user-email">{user.email}</p>
        <p className="lv-action-modal-desc users-delete-user-warning" id="reactivate-user-warning">
          The account will be restored and eligible active listings will appear in the
          marketplace again. Previous sessions stay revoked, so the user must sign in again.
        </p>

        <label className="users-reason-label" htmlFor="reactivate-user-reason">
          Administrative reason
        </label>
        <textarea
          id="reactivate-user-reason"
          className="users-reason-input"
          value={reason}
          maxLength={1000}
          rows={4}
          placeholder="Explain why this account is being reactivated."
          disabled={reactivateUser.isPending}
          onChange={(event) => setReason(event.target.value)}
        />
        <p className="users-reason-help">
          Required. At least 5 characters. This reason is recorded in the audit history.
        </p>

        <div className="lv-action-modal-buttons users-user-dialog-buttons">
          <button
            type="button"
            className="lv-action-cancel"
            disabled={reactivateUser.isPending}
            onClick={onClose}
          >
            Cancel
          </button>
          <button
            type="button"
            className="lv-action-confirm"
            disabled={reactivateUser.isPending || !reasonIsValid}
            onClick={handleReactivate}
          >
            {reactivateUser.isPending ? 'Reactivating…' : 'Confirm Reactivation'}
          </button>
        </div>
      </section>
    </div>
  );
}
