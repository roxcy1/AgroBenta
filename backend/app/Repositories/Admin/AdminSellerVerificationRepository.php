<?php

namespace App\Repositories\Admin;

use App\Enums\SellerVerificationStatus;
use App\Models\SellerVerification;
use Illuminate\Contracts\Pagination\LengthAwarePaginator;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Collection;
use Illuminate\Database\Query\Builder as QueryBuilder;

class AdminSellerVerificationRepository
{
    /**
     * The statuses an application holds while no decision has been made.
     * `pending_review` is the same applicant as `submitted`, filled
     * automatically; neither has been approved or rejected.
     */
    private const OPEN_STATUSES = [
        SellerVerificationStatus::Submitted,
        SellerVerificationStatus::PendingReview,
    ];

    public function list(
        ?string $search = null,
        ?string $status = null,
        int $perPage = 15,
        bool $allSubmissions = false,
    ): LengthAwarePaginator {
        $query = SellerVerification::with(['seller:id,name,email', 'reviewer:id,name']);

        // The cumulative submission log keeps every record, so a resubmission
        // shows beside the earlier one instead of replacing it.
        if (! $allSubmissions) {
            $this->onlyLatestPerUser($query);
        }
        $this->applySearch($query, $search);
        $this->applyFilters($query, $status);

        return $query
            ->orderByDesc('submitted_at')
            ->orderByDesc('id')
            ->paginate($perPage);
    }

    public function find(int $id): ?SellerVerification
    {
        return SellerVerification::with(['seller:id,name,email', 'reviewer:id,name'])
            ->find($id);
    }

    /**
     * Count each applicant's most recent record that is in the given status.
     *
     * Applies the same latest-per-applicant narrowing as the list, so the count
     * agrees with the tab totals rather than counting superseded submissions.
     */
    public function countLatestByStatus(SellerVerificationStatus $status): int
    {
        $query = SellerVerification::query()->where('status', $status);

        $this->onlyLatestPerUser($query);

        return $query->count();
    }

    /**
     * Count each applicant's most recent record that is still open (submitted
     * or pending review): the applications waiting for an administrator.
     */
    public function countLatestOpen(): int
    {
        $query = SellerVerification::query()->whereIn('status', self::OPEN_STATUSES);

        $this->onlyLatestPerUser($query);

        return $query->count();
    }

    /**
     * Resolve the applicant's most recent record. A record is "most recent"
     * when it scores highest on `submitted_at desc, id desc`.
     */
    public function latestForUser(int $userId): ?SellerVerification
    {
        return SellerVerification::query()
            ->where('user_id', $userId)
            ->orderByDesc('submitted_at')
            ->orderByDesc('id')
            ->first();
    }

    /**
     * Prior records for the same applicant, newest first.
     */
    public function historyFor(int $userId, int $excludeId): Collection
    {
        return SellerVerification::with(['seller:id,name,email', 'reviewer:id,name'])
            ->where('user_id', $userId)
            ->whereKeyNot($excludeId)
            ->orderByDesc('submitted_at')
            ->orderByDesc('id')
            ->get();
    }

    /**
     * Keep only the most recent record per applicant so a stale older record
     * is never shown as the applicant's current state.
     */
    private function onlyLatestPerUser(Builder $query): void
    {
        $query->whereNotExists(function (QueryBuilder $sub): void {
            $sub->selectRaw('1')
                ->from('seller_verifications as later')
                ->whereColumn('later.user_id', 'seller_verifications.user_id')
                ->where(function (QueryBuilder $later): void {
                    $later->whereColumn('later.submitted_at', '>', 'seller_verifications.submitted_at')
                        ->orWhere(function (QueryBuilder $tie): void {
                            $tie->whereColumn('later.submitted_at', '=', 'seller_verifications.submitted_at')
                                ->whereColumn('later.id', '>', 'seller_verifications.id');
                        });
                });
        });
    }

    private function applySearch(Builder $query, ?string $search): void
    {
        if ($search === null || $search === '') {
            return;
        }

        $term = '%'.$search.'%';

        $query->where(function (Builder $q) use ($term): void {
            $q->where('business_name', 'like', $term)
                ->orWhereHas('seller', function (Builder $sq) use ($term): void {
                    $sq->where('name', 'like', $term)
                        ->orWhere('email', 'like', $term);
                });
        });
    }

    private function applyFilters(Builder $query, ?string $status): void
    {
        if ($status === null || $status === '') {
            return;
        }

        // `pending` is not a stored status: it is every open application.
        if ($status === 'pending') {
            $query->whereIn('status', self::OPEN_STATUSES);

            return;
        }

        $query->where('status', SellerVerificationStatus::from($status));
    }
}
