<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class SellerDashboardResource extends JsonResource
{
    /**
     * @return array<string, mixed>
     */
    public function toArray(Request $request): array
    {
        return [
            'listings' => $this->resource['listings'],
            'inquiries' => $this->resource['inquiries'],
            'transactions' => $this->resource['transactions'],
        ];
    }
}
