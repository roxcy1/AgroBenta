<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class DashboardResource extends JsonResource
{
    /**
     * Transform the dashboard data into a structured API response.
     *
     * @return array<string, mixed>
     */
    public function toArray(Request $request): array
    {
        return [
            'summary' => $this->resource['summary'],
            'listings' => $this->resource['listings'],
            'transactions' => $this->resource['transactions'],
            'transaction_trend' => $this->resource['transaction_trend'],
            'livestock_distribution' => $this->resource['livestock_distribution'],
            'recent_activities' => $this->resource['recent_activities']->map(function ($activity) {
                return [
                    'id' => $activity->id,
                    'action' => $activity->action,
                    'description' => $activity->description,
                    'created_at' => $activity->created_at?->toISOString(),
                    'user' => $activity->user ? [
                        'id' => $activity->user->id,
                        'name' => $activity->user->name,
                    ] : null,
                ];
            }),
        ];
    }
}
