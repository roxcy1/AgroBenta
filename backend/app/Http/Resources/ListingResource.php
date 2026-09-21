<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class ListingResource extends JsonResource
{
    /**
     * Transform the resource into an array.
     *
     * @return array<string, mixed>
     */
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'seller' => [
                'id' => $this->seller->id,
                'name' => $this->seller->name,
                'email' => $this->seller->email,
            ],
            'livestock_type' => $this->livestock_type,
            'breed' => $this->breed,
            'age_value' => $this->age_value,
            'age_unit' => $this->age_unit,
            'gender' => $this->gender,
            'weight_value' => $this->weight_value,
            'weight_unit' => $this->weight_unit,
            'quantity' => $this->quantity,
            'asking_price' => $this->asking_price,
            'location' => $this->location,
            'health_status' => $this->health_status,
            'vaccination' => $this->vaccination,
            'short_description' => $this->short_description,
            'additional_notes' => $this->additional_notes,
            'status' => $this->status?->value,
            'created_at' => $this->created_at?->toISOString(),
            'updated_at' => $this->updated_at?->toISOString(),
        ];
    }
}
