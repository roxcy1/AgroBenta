<?php

namespace App\Repositories\Admin;

use App\Models\Setting;
use Illuminate\Support\Collection;

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
     * Upsert multiple settings by key.
     *
     * @param  array<string, string>  $values  key => value pairs
     */
    public function updateMany(array $values): void
    {
        foreach ($values as $key => $value) {
            Setting::query()
                ->where('key', $key)
                ->update(['value' => $value]);
        }
    }
}
