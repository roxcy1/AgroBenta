<?php

namespace App\Services\Admin;

use App\Enums\ActivityAction;
use App\Enums\UserRole;
use App\Models\User;
use App\Repositories\Admin\AdminUserRepository;
use App\Services\ActivityLogger;
use Illuminate\Contracts\Pagination\LengthAwarePaginator;
use Illuminate\Support\Facades\DB;
use Symfony\Component\HttpKernel\Exception\HttpExceptionInterface;

class AdminUserService
{
    public function __construct(
        private readonly AdminUserRepository $users,
        private readonly ActivityLogger $activity,
    ) {}

    public function listUsers(
        ?string $search = null,
        ?string $role = null,
        ?string $sellerCapability = null,
        ?string $status = null,
        int $perPage = 15,
    ): LengthAwarePaginator {
        return $this->users->list($search, $role, $sellerCapability, $status, $perPage);
    }

    /**
     * Load the admin detail projection for one user, including a trashed row.
     */
    public function showUser(User $user): User
    {
        return $this->users->loadMetrics($user);
    }

    /**
     * Update only the two administrator-editable user attributes.
     *
     * @param  array{name: string, email: string}  $attributes
     */
    public function updateUser(User $user, array $attributes, User $actor): User
    {
        return DB::transaction(function () use ($user, $attributes, $actor): User {
            $current = $this->users->findForUpdate((int) $user->getKey());
            abort_if($current === null, 404, 'User not found.');

            $changes = [];
            foreach (['name', 'email'] as $field) {
                if ($current->{$field} !== $attributes[$field]) {
                    $changes[$field] = [
                        'from' => $current->{$field},
                        'to' => $attributes[$field],
                    ];
                }
            }

            $updated = $this->users->update($current, $attributes);

            if ($changes !== []) {
                $this->activity->log(
                    $actor,
                    ActivityAction::AdminUserUpdated,
                    sprintf('User account #%d updated.', $updated->getKey()),
                    [
                        'target_type' => 'user',
                        'target_id' => $updated->getKey(),
                        'changes' => $changes,
                    ],
                );
            }

            return $this->users->loadMetrics($updated);
        });
    }

    /**
     * Deactivate an account without deleting its listings or business history.
     *
     * The administrative reason is required, persisted on the account, and
     * copied into the audit entry. The existing self/last-administrator guards
     * remain the authority; no report may bypass them.
     *
     * @throws HttpExceptionInterface
     */
    public function deleteUser(User $user, User $actor, string $reason): User
    {
        $reason = trim($reason);
        abort_if($reason === '', 422, 'An administrative reason is required.');

        return DB::transaction(function () use ($user, $actor, $reason): User {
            // Lock administrators in a stable order before the target row.
            // Concurrent attempts to remove different admins therefore
            // serialize here instead of deadlocking while holding opposite
            // target-row locks.
            $activeAdministrators = $this->users->lockActiveAdministrators();
            $target = $this->users->findForUpdate((int) $user->getKey());
            abort_if($target === null, 404, 'User not found.');

            abort_if(
                $target->is($actor),
                409,
                'Administrators cannot delete their own account.',
            );

            if ($target->role === UserRole::Admin) {
                abort_if(
                    $activeAdministrators->count() <= 1,
                    409,
                    'The last active administrator cannot be deleted.',
                );
            }

            $targetId = (int) $target->getKey();
            $targetName = $target->name;
            $targetEmail = $target->email;

            $this->users->markDeactivated($target, $actor, $reason);
            $this->users->revokeCredentials($target);

            // The audit record is written in the same transaction and before
            // the soft delete, so both actor and target remain attributable.
            $this->activity->log(
                $actor,
                ActivityAction::AdminUserDeleted,
                sprintf('User account #%d deactivated.', $targetId),
                [
                    'target_type' => 'user',
                    'target_id' => $targetId,
                    'context' => [
                        'name' => $targetName,
                        'email' => $targetEmail,
                        'reason' => $reason,
                    ],
                    'changes' => [
                        'status' => ['from' => 'active', 'to' => 'deactivated'],
                    ],
                ],
            );

            $this->users->softDelete($target);

            return $this->users->loadMetrics($target);
        });
    }

    /**
     * Restore a previously deactivated account.
     *
     * Credentials stay revoked: reactivation restores the account, not an old
     * session. Listings are untouched, so eligible active listings reappear
     * through the existing seller-visibility rule.
     *
     * @throws HttpExceptionInterface
     */
    public function reactivateUser(User $user, User $actor, string $reason): User
    {
        $reason = trim($reason);
        abort_if($reason === '', 422, 'An administrative reason is required.');

        return DB::transaction(function () use ($user, $actor, $reason): User {
            // Reactivation is not a last-administrator operation: it only adds
            // an active administrator back. Lock the target row for a stable
            // read of its current state.
            $target = $this->users->findTrashedForUpdate((int) $user->getKey());
            abort_if($target === null, 404, 'User not found.');
            abort_unless(
                $target->trashed(),
                409,
                'This account is already active.',
            );

            $targetId = (int) $target->getKey();
            $targetName = $target->name;
            $targetEmail = $target->email;

            $this->activity->log(
                $actor,
                ActivityAction::AdminUserReactivated,
                sprintf('User account #%d reactivated.', $targetId),
                [
                    'target_type' => 'user',
                    'target_id' => $targetId,
                    'context' => [
                        'name' => $targetName,
                        'email' => $targetEmail,
                        'reason' => $reason,
                    ],
                    'changes' => [
                        'status' => ['from' => 'deactivated', 'to' => 'active'],
                    ],
                ],
            );

            $this->users->restore($target);
            $target->forceFill([
                'deactivation_reason' => null,
                'deactivated_by' => null,
            ])->save();

            // Keep the previous session revoked even if a future change starts
            // preserving tokens across soft deletes.
            $this->users->revokeCredentials($target);

            return $this->users->loadMetrics($target->refresh());
        });
    }
}
