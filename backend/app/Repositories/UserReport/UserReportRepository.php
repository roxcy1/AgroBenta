<?php

namespace App\Repositories\UserReport;

use App\Enums\UserReportStatus;
use App\Models\User;
use App\Models\UserReport;

class UserReportRepository
{
    /**
     * Lock the reported account row so concurrent reports for the same target
     * serialize before the duplicate-pending check. Trashed accounts are
     * included so the service can refuse a deactivated target explicitly.
     */
    public function lockReportedUser(int $id): ?User
    {
        return User::withTrashed()
            ->whereKey($id)
            ->lockForUpdate()
            ->first();
    }

    public function hasPendingBetween(int $reporterId, int $reportedUserId): bool
    {
        return UserReport::query()
            ->where('reporter_id', $reporterId)
            ->where('reported_user_id', $reportedUserId)
            ->where('status', UserReportStatus::Pending)
            ->exists();
    }

    /**
     * @param  array{reporter_id: int, reported_user_id: int, reason: string, description: string, evidence_path?: string|null}  $attributes
     */
    public function create(array $attributes): UserReport
    {
        return UserReport::query()->create($attributes);
    }
}
