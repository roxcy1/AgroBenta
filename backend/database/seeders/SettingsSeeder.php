<?php

namespace Database\Seeders;

use App\Models\Setting;
use Illuminate\Database\Seeder;

class SettingsSeeder extends Seeder
{
    /**
     * Seed the default system settings.
     */
    public function run(): void
    {
        $settings = [
            [
                'key' => 'system.name',
                'value' => 'AgroBenta',
                'group' => 'system',
                'label' => 'System Name',
                'description' => 'The display name of the platform.',
            ],
            [
                'key' => 'system.description',
                'value' => 'A livestock trading platform connecting buyers and sellers.',
                'group' => 'system',
                'label' => 'System Description',
                'description' => 'A brief description of the platform.',
            ],
            [
                'key' => 'admin_contact.name',
                'value' => 'Administrator',
                'group' => 'admin_contact',
                'label' => 'Contact Name',
                'description' => 'Name displayed as the platform contact.',
            ],
            [
                'key' => 'admin_contact.email',
                'value' => 'admin@agrobenta.example.com',
                'group' => 'admin_contact',
                'label' => 'Contact Email',
                'description' => 'Email address for platform inquiries.',
            ],
            [
                'key' => 'admin_contact.phone',
                'value' => '',
                'group' => 'admin_contact',
                'label' => 'Contact Phone',
                'description' => 'Phone number for platform inquiries.',
            ],
        ];

        foreach ($settings as $setting) {
            Setting::updateOrCreate(
                ['key' => $setting['key']],
                [
                    'value' => $setting['value'],
                    'group' => $setting['group'],
                    'label' => $setting['label'],
                    'description' => $setting['description'],
                ],
            );
        }
    }
}
