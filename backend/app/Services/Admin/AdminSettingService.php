<?php

namespace App\Services\Admin;

use App\Enums\ActivityAction;
use App\Http\Requests\Admin\UpdateSettingsRequest;
use App\Models\Setting;
use App\Models\User;
use App\Repositories\Admin\AdminSettingRepository;
use App\Services\ActivityLogger;
use App\Services\SettingService;
use Illuminate\Support\Collection;
use Illuminate\Support\Facades\DB;

class AdminSettingService
{
    public function __construct(
        private readonly AdminSettingRepository $settings,
        private readonly SettingService $settingService,
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
     * Update multiple settings at once. Only registered keys are accepted.
     *
     * The allow-list is the settings registry itself, so a key cannot be
     * updatable through the API without existing as a described setting with
     * validation rules — there is no second list to drift from.
     *
     * Values have already been validated by {@see UpdateSettingsRequest};
     * this method only decides which keys are known and writes them.
     *
     * @param  array<string, string>  $input  key => value pairs from the request
     * @return array{updated: list<string>, rejected: list<string>}
     */
    public function updateSettings(array $input, User $actor): array
    {
        $definitions = config('settings.keys');
        $rows = [];
        $rejected = [];

        foreach ($input as $key => $value) {
            $definition = $definitions[$key] ?? null;

            if ($definition === null) {
                $rejected[] = $key;

                continue;
            }

            $rows[$key] = [
                'value' => (string) $value,
                'group' => $definition['group'],
                'label' => $definition['label'],
                'description' => $definition['description'],
            ];
        }

        if ($rows !== []) {
            DB::transaction(function () use ($rows, $actor): void {
                $changes = [];

                foreach ($rows as $key => $row) {
                    $setting = $this->settings->findByKey($key);

                    // A key that has no row is a no-op for the write below, so
                    // it is not recorded as a change either.
                    if ($setting === null || $setting->value === $row['value']) {
                        continue;
                    }

                    $changes[$key] = ['from' => $setting->value, 'to' => $row['value']];
                }

                $this->settings->updateMany($rows);

                // The write path owns cache correctness: the reader caches the whole
                // map, so dropping it here is what makes an update visible at once.
                $this->settingService->flush();

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
            'updated' => array_keys($rows),
            'rejected' => $rejected,
        ];
    }
}
