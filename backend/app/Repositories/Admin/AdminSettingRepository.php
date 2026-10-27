<?php

namespace App\Repositories\Admin;

use App\Models\Setting;
use Illuminate\Support\Collection;
use Illuminate\Support\Facades\DB;

class AdminSettingRepository
{
    /**
     * Get all settings ordered by group and label.
     */
    public function all(): Collection
    {
        return Setting::query()
            ->orderBy('group')
            ->orderBy('label')
            ->get();
    }

    /**
     * Get settings grouped by the `group` column.
     *
     * @return array<string, Collection<int, Setting>>
     */
    public function grouped(): array
    {
        return $this->all()->groupBy('group')->all();
    }

    /**
     * Find a setting by its unique key.
     */
    public function findByKey(string $key): ?Setting
    {
        return Setting::query()->where('key', $key)->first();
    }

    /**
     * Upsert multiple settings by key, atomically.
     *
     * The whole batch runs in one transaction so a failure part-way through
     * leaves none of the settings changed, rather than a request that reports
     * failure and has still half-applied to the database.
     *
     * `updateOrCreate`, not an update-only `where('key')`: a key that is
     * registered but somehow absent from the table (a deployment that has not
     * been seeded) is created rather than silently skipped, so an accepted
     * update is always visible in the next read.
     *
     * @param  array<string, array{value: string, group: string, label: string, description: ?string}>  $rows
     */
    public function updateMany(array $rows): void
    {
        DB::transaction(function () use ($rows): void {
            foreach ($rows as $key => $attributes) {
                Setting::query()->updateOrCreate(['key' => $key], $attributes);
            }
        });
    }
}
