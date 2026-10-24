<?php

namespace App\Repositories\Admin;

use App\Models\Activity;
use Illuminate\Contracts\Pagination\LengthAwarePaginator;
use Illuminate\Database\Eloquent\Builder;

class AdminActivityRepository
{
    public function list(
        ?string $search = null,
        $action = null,
        ?string $userId = null,
        ?string $dateFrom = null,
        ?string $dateTo = null,
        int $perPage = 15,
    ): LengthAwarePaginator {
        $query = Activity::query()
            ->with(['user:id,name,email']);

        $this->applySearch($query, $search);
        $this->applyFilters($query, $action, $userId, $dateFrom, $dateTo);

        return $query
            ->orderByDesc('created_at')
            ->paginate($perPage);
    }

    private function applySearch(Builder $query, ?string $search): void
    {
        if ($search === null || $search === '') {
            return;
        }

        $term = '%'.$search.'%';

        $query->where(function (Builder $q) use ($term): void {
            $q->where('action', 'like', $term)
                ->orWhere('description', 'like', $term)
                ->orWhereHas('user', function (Builder $q2) use ($term): void {
                    $q2->where('name', 'like', $term)
                        ->orWhere('email', 'like', $term);
                });
        });
    }

    private function applyFilters(Builder $query, $action, ?string $userId, ?string $dateFrom, ?string $dateTo): void
    {
        $actions = [];

        if (is_array($action)) {
            $actions = array_values(array_filter($action, function ($value) {
                return is_string($value) && $value !== '';
            }));
        } elseif (is_string($action) && $action !== '') {
            if (str_contains($action, ',')) {
                $actions = array_values(array_filter(array_map('trim', explode(',', $action)), function ($value) {
                    return $value !== '';
                }));
            } else {
                $actions = [$action];
            }
        }

        if (! empty($actions)) {
            if (count($actions) === 1) {
                $query->where('action', $actions[0]);
            } else {
                $query->whereIn('action', $actions);
            }
        }

        if ($userId !== null && $userId !== '') {
            $query->where('user_id', $userId);
        }

        if ($dateFrom !== null && $dateFrom !== '') {
            $query->where('created_at', '>=', $dateFrom);
        }

        if ($dateTo !== null && $dateTo !== '') {
            $query->where('created_at', '<=', $dateTo.' 23:59:59');
        }
    }

    public function getSummaryLast24Hours(): array
    {
        $since = now()->subDay();

        $total = Activity::query()
            ->where('created_at', '>=', $since)
            ->count();

        $activeActors = Activity::query()
            ->where('created_at', '>=', $since)
            ->whereNotNull('user_id')
            ->distinct()
            ->count('user_id');

        $moderationActions = Activity::query()
            ->where('created_at', '>=', $since)
            ->whereIn('action', [
                'listing_approved',
                'listing_rejected',
                'listing_deactivated',
                'seller_verification_approved',
                'seller_verification_rejected',
            ])
            ->count();

        $configurationChanges = Activity::query()
            ->where('created_at', '>=', $since)
            ->where('action', 'settings_updated')
            ->count();

        return [
            'total_activities' => $total,
            'active_actors' => $activeActors,
            'moderation_actions' => $moderationActions,
            'configuration_changes' => $configurationChanges,
            'window' => 'last_24h',
            'since' => $since->toISOString(),
            'until' => now()->toISOString(),
        ];
    }
}
