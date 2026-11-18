<?php

namespace App\Repositories\Admin;

use App\Enums\TransactionStatus;
use App\Enums\UserReportStatus;
use App\Models\UserReport;
use Illuminate\Contracts\Pagination\LengthAwarePaginator;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class AdminUserReportRepository
{
    public function list(?string $status = null, int $perPage = 15): LengthAwarePaginator
    {
        return UserReport::query()
            ->with([
                'reporter:id,name',
                'reportedUser' => fn (BelongsTo $query): BelongsTo => $this->withReportedUserMetrics($query),
                'reviewer:id,name',
            ])
            ->when($status !== null && $status !== '', function ($query) use ($status): void {
                $query->where('status', $status);
            })
            ->orderByDesc('created_at')
            ->orderByDesc('id')
            ->paginate($perPage);
    }

    public function find(int $id): ?UserReport
    {
        return UserReport::query()
            ->with([
                'reporter:id,name',
                'reportedUser' => fn (BelongsTo $query): BelongsTo => $this->withReportedUserMetrics($query),
                'reviewer:id,name',
            ])
            ->find($id);
    }

    public function lock(int $id): ?UserReport
    {
        return UserReport::query()->whereKey($id)->lockForUpdate()->first();
    }

    public function markDismissed(UserReport $report, int $reviewerId, ?string $note): UserReport
    {
        $report->forceFill([
            'status' => UserReportStatus::Dismissed,
            'reviewed_by' => $reviewerId,
            'reviewed_at' => now(),
            'admin_note' => $note,
        ])->save();

        return $report->refresh();
    }

    public function markActioned(UserReport $report, int $reviewerId, string $note): UserReport
    {
        $report->forceFill([
            'status' => UserReportStatus::Actioned,
            'reviewed_by' => $reviewerId,
            'reviewed_at' => now(),
            'admin_note' => $note,
        ])->save();

        return $report->refresh();
    }

    /**
     * Keep the reported user's account status and pending-transaction warning
     * on the moderation projection. The count is loaded in SQL, never per row.
     */
    private function withReportedUserMetrics(BelongsTo $query): BelongsTo
    {
        return $query
            ->select(['id', 'name', 'deleted_at'])
            ->withCount([
                'transactionsAsBuyer as pending_buyer_transactions_count' => fn (Builder $count): Builder => $count
                    ->where('status', TransactionStatus::Pending),
                'transactionsAsSeller as pending_seller_transactions_count' => fn (Builder $count): Builder => $count
                    ->where('status', TransactionStatus::Pending),
            ]);
    }
}
