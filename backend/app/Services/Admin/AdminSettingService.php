<?php

namespace App\Services\Admin;

use App\Enums\ActivityAction;
use App\Models\Setting;
use App\Models\User;
use App\Repositories\Admin\AdminSettingRepository;
use App\Services\ActivityLogger;
use Illuminate\Support\Collection;
use Illuminate\Support\Facades\DB;

class AdminSettingService
{
    private const ALLOWED_KEYS = [
        'system.name',
        'system.description',
        'admin_contact.name',
        'admin_contact.email',
        'admin_contact.phone',
    ];

    public function __construct(
        private readonly AdminSettingRepository $settings,
        private readonly ActivityLogger $activity,
    ) {
        //
    }

    /**
     * Return all settings grouped by group.
     *
     * @return array<string, Collection<int, Setting>>
     */
    public function getAllGrouped(): array
    {
        return $this->settings->grouped();
    }

    /**
     * Update multiple settings at once. Only allowlisted keys are accepted.
     *
     * @param  array<string, string>  $input  key => value pairs from the request
     * @return array{updated: list<string>, rejected: list<string>}
     */
    public function updateSettings(array $input, User $actor): array
    {
        $allowed = [];
        $rejected = [];

        foreach ($input as $key => $value) {
            if (in_array($key, self::ALLOWED_KEYS, true)) {
                $allowed[$key] = (string) $value;
            } else {
                $rejected[] = $key;
            }
        }

        if ($allowed !== []) {
            DB::transaction(function () use ($allowed, $actor): void {
                $changes = [];

                foreach ($allowed as $key => $value) {
                    $setting = $this->settings->findByKey($key);

                    // A key that has no row is a no-op for the write below, so
                    // it is not recorded as a change either.
                    if ($setting === null || $setting->value === $value) {
                        continue;
                    }

                    $changes[$key] = ['from' => $setting->value, 'to' => $value];
                }

                $this->settings->updateMany($allowed);

                if ($changes !== []) {
                    $this->activity->log(
                        $actor,
                        ActivityAction::SettingsUpdated,
                        'Platform settings updated.',
                        [
                            'target_type' => 'setting',
                            'target_id' => null,
                            'changes' => $changes,
                        ],
                    );
                }
            });
        }

        return [
            'updated' => array_keys($allowed),
            'rejected' => $rejected,
        ];
    }
}
