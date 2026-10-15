<?php

namespace Database\Seeders;

use App\Models\Setting;
use Illuminate\Database\Seeder;

class SettingsSeeder extends Seeder
{
    /**
     * Seed the default settings from the registry.
     *
     * The registry in `config/settings.php` is the single source of truth for
     * which keys exist, their presentation metadata, and their defaults; the
     * seeder only materialises them as rows. Idempotent, so re-running it never
     * duplicates a key or clobbers an administrator's saved value beyond the
     * documented default.
     */
    public function run(): void
    {
        foreach (config('settings.keys') as $key => $definition) {
            Setting::updateOrCreate(
                ['key' => $key],
                [
                    'value' => $definition['default'],
                    'group' => $definition['group'],
                    'label' => $definition['label'],
                    'description' => $definition['description'],
                ],
            );
        }
    }
}
