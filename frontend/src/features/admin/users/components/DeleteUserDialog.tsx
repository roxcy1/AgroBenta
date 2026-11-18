import { useEffect, useState } from 'react';
import { useToast } from '../../../../lib/toast/ToastProvider';
import { useDeleteAdminUser, type AdminUser } from '../api/useUsers';
import { apiUserErrorMessage } from '../userValidation';

interface DeleteUserDialogProps {
  user: AdminUser;
  onClose: () => void;
  onDeactivated: () => void;
}

export default function DeleteUserDialog({ user, onClose, onDeactivated }: DeleteUserDialogProps) {
  const deleteUser = useDeleteAdminUser();
  const toast = useToast();
  const [reason, setReason] = useState('');
  const trimmedReason = reason.trim();
  const reasonIsValid = trimmedReason.length >= 5;

  useEffect(() => {
    function handleKeyDown(event: KeyboardEvent) {
      if (event.key === 'Escape' && !deleteUser.isPending) onClose();
    }

    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, [onClose, deleteUser.isPending]);

  function handleDeactivate() {
    if (!reasonIsValid) return;

    deleteUser.mutate(
      { id: user.id, reason: trimmedReason },
      {
        onSuccess: () => {
          toast.success('User account deactivated.');
          onDeactivated();
          onClose();
        },
        onError: (error) => {
          const message = apiUserErrorMessage(
            error,
            'Unable to deactivate this user. Please try again.',
          );
          toast.error(message);
        },
      },
    );
  }

  function closeIfIdle() {
    if (!deleteUser.isPending) onClose();
  }

  const pendingTransactions = user.pending_transactions_count ?? 0;

  return (
    <div className="lv-action-modal-overlay" onClick={closeIfIdle}>
      <section
        className="lv-action-modal users-user-dialog"
        role="alertdialog"
        aria-modal="true"
        aria-labelledby="deactivate-user-title"
        aria-describedby="deactivate-user-warning"
        onClick={(event) => event.stopPropagation()}
      >
        <h2 className="lv-action-modal-title" id="deactivate-user-title">Deactivate Account</h2>
        <p className="users-delete-user-identity">{user.name}</p>
        <p className="users-delete-user-email">{user.email}</p>
        <p className="lv-action-modal-desc users-delete-user-warning" id="deactivate-user-warning">
          This immediately revokes the account&apos;s active sessions and hides its listings
          from the marketplace. Listing, seller verification, message, and transaction history
          are retained. The email address remains reserved while the account is deactivated.
        </p>

        {pendingTransactions > 0 && (
          <p className="users-deactivate-warning" role="alert">
            This account is part of {pendingTransactions} pending transaction
            {pendingTransactions === 1 ? '' : 's'}. The transaction records and reserved stock
            will be preserved; nothing is cancelled automatically.
          </p>
        )}

        <label className="users-reason-label" htmlFor="deactivate-user-reason">
          Administrative reason
        </label>
        <textarea
          id="deactivate-user-reason"
          className="users-reason-input"
          value={reason}
          maxLength={1000}
          rows={4}
          placeholder="Explain why this account is being deactivated."
          disabled={deleteUser.isPending}
          onChange={(event) => setReason(event.target.value)}
        />
        <p className="users-reason-help">
          Required. At least 5 characters. This reason is recorded in the audit history.
        </p>

        <div className="lv-action-modal-buttons users-user-dialog-buttons">
          <button
            type="button"
            className="lv-action-cancel"
            disabled={deleteUser.isPending}
            onClick={onClose}
          >
            Cancel
          </button>
          <button
            type="button"
            className="lv-action-confirm users-delete-confirm"
            disabled={deleteUser.isPending || !reasonIsValid}
            onClick={handleDeactivate}
          >
            {deleteUser.isPending ? 'Deactivating…' : 'Confirm Deactivation'}
          </button>
        </div>
      </section>
    </div>
  );
}
