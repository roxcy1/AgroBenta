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
        int $perPage = 15,
    ): LengthAwarePaginator {
        return $this->users->list($search, $role, $sellerCapability, $perPage);
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

            return $updated;
        });
    }

    /**
     * Deactivate an account without deleting its listings or business history.
     *
     * @throws HttpExceptionInterface
     */
    public function deleteUser(User $user, User $actor): User
    {
        return DB::transaction(function () use ($user, $actor): User {
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
                    ],
                ],
            );

            $this->users->softDelete($target);

            return $target;
        });
    }
}
