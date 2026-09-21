<?php

namespace App\Services\Admin;

use App\Models\Setting;
use App\Repositories\Admin\AdminSettingRepository;
use Illuminate\Support\Collection;

class AdminSettingService
{
    private const ALLOWED_KEYS = [
        'system.name',
        'system.description',
        'admin_contact.name',
        'admin_contact.email',
        'admin_contact.phone',
    ];

    public function __construct(private readonly AdminSettingRepository $settings)
    {
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
    public function updateSettings(array $input): array
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
            $this->settings->updateMany($allowed);
        }

        return [
            'updated' => array_keys($allowed),
            'rejected' => $rejected,
        ];
    }
}
