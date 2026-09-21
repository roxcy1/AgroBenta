<?php

namespace App\Http\Resources;

use App\Models\Setting;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * @property-read string $key
 * @property-read string $value
 * @property-read string $group
 * @property-read string $label
 * @property-read string|null $description
 */
class SettingResource extends JsonResource
{
    public function __construct(Setting $setting)
    {
        parent::__construct($setting);
    }

    /**
     * @return array<string, mixed>
     */
    public function toArray(Request $request): array
    {
        return [
            'key' => $this->key,
            'value' => $this->value,
            'group' => $this->group,
            'label' => $this->label,
            'description' => $this->description,
        ];
    }
}
