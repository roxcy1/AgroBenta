<?php

namespace App\Services\Notification;

use App\Models\NotificationPreference;
use App\Models\User;

/**
 * Reads and saves a user's push switches, and decides whether a stored
 * notification is pushed to their phones.
 *
 * Missing row means every category is on.
 */
class NotificationPreferenceService
{
    /**
     * The user's switches, every category present.
     *
     * @return array<string, bool>
     */
    public function forUser(User $user): array
    {
        $preference = $user->notificationPreference;

        $values = [];
        foreach (NotificationPreference::CATEGORIES as $category) {
            $values[$category] = $preference === null ? true : (bool) $preference->{$category};
        }

        return $values;
    }

    /**
     * Saves the given switches; categories not given keep their value.
     *
     * @param  array<string, bool>  $changes
     * @return array<string, bool>
     */
    public function update(User $user, array $changes): array
    {
        $user->notificationPreference()->updateOrCreate(
            ['user_id' => $user->getKey()],
            array_intersect_key($changes, array_flip(NotificationPreference::CATEGORIES)),
        );

        return $this->forUser($user->refresh());
    }

    /**
     * Whether a notification of [$type] is pushed to the user's phones.
     */
    public function allowsPush(User $user, ?string $type): bool
    {
        $category = NotificationPreference::CATEGORY_BY_TYPE[$type ?? ''] ?? null;

        if ($category === null) {
            return true;
        }

        return $this->forUser($user)[$category];
    }
}
