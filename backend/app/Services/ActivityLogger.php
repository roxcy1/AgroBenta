<?php

namespace App\Services;

use App\Enums\ActivityAction;
use App\Models\Activity;
use App\Models\User;

/**
 * The single writer for the activity log.
 *
 * Deliberately small: an entry is an actor, an action, a human-readable
 * description and a metadata bag. Callers own the metadata shape, following the
 * agreed convention `{ target_type, target_id, changes, ...context }`, so this
 * class never has to grow per feature.
 *
 * The actor is recorded in the existing `user_id` column; `null` is a genuine
 * "system" entry, not a placeholder. Nothing here writes a password, token or
 * credential — audit must never become a second copy of a secret.
 */
class ActivityLogger
{
    /**
     * Write an audit entry.
     *
     * @param  User|int|null  $actor  The acting account, its id, or null for the system.
     * @param  array<string, mixed>  $metadata  Target reference, changes and context.
     */
    public function log(
        User|int|null $actor,
        ActivityAction $action,
        ?string $description = null,
        array $metadata = [],
    ): Activity {
        return Activity::query()->create([
            'user_id' => $actor instanceof User ? $actor->getKey() : $actor,
            'action' => $action->value,
            'description' => $description,
            'metadata' => $metadata === [] ? null : $metadata,
        ]);
    }

    /**
     * Write an entry that must not be able to break the action it records.
     *
     * Authentication is the only caller that opts into this: a login that
     * succeeded must not fail because the audit insert did. The failure is
     * reported to the exception handler (and so to the log) rather than
     * swallowed silently.
     *
     * @param  array<string, mixed>  $metadata
     */
    public function logSafely(
        User|int|null $actor,
        ActivityAction $action,
        ?string $description = null,
        array $metadata = [],
    ): void {
        try {
            $this->log($actor, $action, $description, $metadata);
        } catch (\Throwable $exception) {
            report($exception);
        }
    }
}
