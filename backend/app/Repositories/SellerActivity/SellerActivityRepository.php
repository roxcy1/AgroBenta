<?php

namespace App\Repositories\SellerActivity;

use App\Enums\ActivityAction;
use App\Models\Activity;
use App\Models\User;
use Illuminate\Contracts\Pagination\LengthAwarePaginator;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Support\Carbon;
use Illuminate\Support\Collection;

/**
 * Seller-scoped reads over the existing `activities` audit table.
 *
 * The feed is a projection of genuine events that `ActivityLogger` already
 * wrote; nothing is inferred and no notification rows are merged, so one action
 * cannot appear twice. Ownership is applied here, in the query, from the
 * token's seller — never from a client value.
 */
class SellerActivityRepository
{
    /**
     * The only actions a seller may see in this feed.
     *
     * @var list<ActivityAction>
     */
    public const ALLOWED_ACTIONS = [
        ActivityAction::InquiryCreated,
        ActivityAction::ListingApproved,
        ActivityAction::ListingRejected,
        ActivityAction::OfferCreated,
        ActivityAction::OfferAccepted,
        ActivityAction::OfferDeclined,
        ActivityAction::OfferWithdrawn,
        ActivityAction::ListingMarkedSold,
        ActivityAction::TransactionCancelled,
    ];

    /**
     * The All Activities category chips mapped to their actions.
     *
     * @var array<string, list<ActivityAction>>
     */
    public const CATEGORIES = [
        'listings' => [
            ActivityAction::ListingApproved,
            ActivityAction::ListingRejected,
            ActivityAction::ListingMarkedSold,
        ],
        'inquiries' => [
            ActivityAction::InquiryCreated,
        ],
        'offers' => [
            ActivityAction::OfferCreated,
            ActivityAction::OfferAccepted,
            ActivityAction::OfferDeclined,
            ActivityAction::OfferWithdrawn,
        ],
        'transactions' => [
            ActivityAction::TransactionCancelled,
        ],
    ];

    /**
     * The newest seller-relevant events for Seller Home.
     *
     * @return Collection<int, Activity>
     */
    public function latestForSeller(User $seller, int $limit = 5): Collection
    {
        return $this->baseQuery($seller)
            ->limit($limit)
            ->get();
    }

    /**
     * One page of the seller's activities for the All Activities screen.
     *
     * Filters are applied before pagination; ordering is deterministic.
     *
     * @return LengthAwarePaginator<int, Activity>
     */
    public function paginateForSeller(
        User $seller,
        int $perPage = 15,
        int $page = 1,
        ?string $category = null,
        ?string $from = null,
        ?string $to = null,
    ): LengthAwarePaginator {
        $query = $this->baseQuery($seller);

        if ($category !== null && isset(self::CATEGORIES[$category])) {
            $query->whereIn('action', array_map(
                static fn (ActivityAction $action): string => $action->value,
                self::CATEGORIES[$category],
            ));
        }

        if ($from !== null) {
            $query->where('created_at', '>=', Carbon::parse($from)->startOfDay());
        }

        if ($to !== null) {
            $query->where('created_at', '<=', Carbon::parse($to)->endOfDay());
        }

        return $query
            ->orderByDesc('created_at')
            ->orderByDesc('id')
            ->paginate($perPage, ['*'], 'page', $page);
    }

    /**
     * Allow-listed, seller-owned events, newest first.
     *
     * Ownership is **not** "actor is the seller": a seller may also be a buyer,
     * and their `inquiry_created` event belongs to the seller of that listing,
     * not to them. Events that name the seller in `context.seller_id` (inquiry,
     * offer, moderation, transaction) are owned by that id exclusively. Only
     * `listing_marked_sold`, which carries no context, falls back to the actor
     * (`user_id`), because the seller performs it themselves.
     */
    private function baseQuery(User $seller): Builder
    {
        $sellerId = $seller->getKey();

        return Activity::query()
            ->whereIn('action', array_map(
                static fn (ActivityAction $action): string => $action->value,
                self::ALLOWED_ACTIONS,
            ))
            ->where(function (Builder $query) use ($sellerId): void {
                $query->where('metadata->context->seller_id', $sellerId)
                    ->orWhere(function (Builder $query) use ($sellerId): void {
                        $query->where('action', ActivityAction::ListingMarkedSold->value)
                            ->where('user_id', $sellerId);
                    });
            });
    }
}
