import { useEffect } from 'react';
import { useToast } from '../../../../lib/toast/ToastProvider';
import { useDeleteAdminUser, type AdminUser } from '../api/useUsers';
import { apiUserErrorMessage } from '../userValidation';

interface DeleteUserDialogProps {
  user: AdminUser;
  onClose: () => void;
  onDeleted: () => void;
}

export default function DeleteUserDialog({ user, onClose, onDeleted }: DeleteUserDialogProps) {
  const deleteUser = useDeleteAdminUser();
  const toast = useToast();

  useEffect(() => {
    function handleKeyDown(event: KeyboardEvent) {
      if (event.key === 'Escape' && !deleteUser.isPending) onClose();
    }

    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, [onClose, deleteUser.isPending]);

  function handleDelete() {
    deleteUser.mutate(user.id, {
      onSuccess: () => {
        toast.success('User deleted successfully.');
        onDeleted();
        onClose();
      },
      onError: (error) => {
        const message = apiUserErrorMessage(error, 'Unable to delete this user. Please try again.');
        toast.error(message);
      },
    });
  }

  function closeIfIdle() {
    if (!deleteUser.isPending) onClose();
  }

  return (
    <div className="lv-action-modal-overlay" onClick={closeIfIdle}>
      <section
        className="lv-action-modal users-user-dialog"
        role="alertdialog"
        aria-modal="true"
        aria-labelledby="delete-user-title"
        aria-describedby="delete-user-warning"
        onClick={(event) => event.stopPropagation()}
      >
        <h2 className="lv-action-modal-title" id="delete-user-title">Delete User</h2>
        <p className="users-delete-user-identity">{user.name}</p>
        <p className="users-delete-user-email">{user.email}</p>
        <p className="lv-action-modal-desc users-delete-user-warning" id="delete-user-warning">
          This deactivates the account and revokes its active sessions. The user will no longer
          appear in Users or the buyer marketplace. Listing, seller verification, message, and
          transaction history will be retained. The email address remains reserved.
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
            disabled={deleteUser.isPending}
            onClick={handleDelete}
          >
            {deleteUser.isPending ? 'Deleting…' : 'Confirm Delete'}
          </button>
        </div>
      </section>
    </div>
  );
}
