<?php

namespace App\Repositories\Admin;

use App\Enums\ListingStatus;
use App\Enums\SellerCapability;
use App\Enums\TransactionStatus;
use App\Enums\UserRole;
use App\Models\Activity;
use App\Models\Listing;
use App\Models\SellerVerification;
use App\Models\Transaction;
use App\Models\User;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Support\Collection;

class AdminReportRepository
{
    /**
     * Get marketplace overview metrics.
     *
     * @return array{total_users: int, buyer_accounts: int, approved_sellers: int, total_listings: int, active_listings: int, sold_listings: int, pending_listings: int, total_transactions: int, pending_transactions: int, completed_transactions: int, cancelled_transactions: int}
     */
    public function getMarketplaceOverview(?string $dateFrom = null, ?string $dateTo = null): array
    {
        $userQuery = User::query();
        $listingQuery = Listing::query();
        $transactionQuery = Transaction::query();

        $this->applyDateFilter($transactionQuery, $dateFrom, $dateTo);

        return [
            'total_users' => $userQuery->count(),
            'buyer_accounts' => User::where('role', UserRole::User)
                ->where('seller_capability', SellerCapability::Buyer)
                ->count(),
            'approved_sellers' => User::where('seller_capability', SellerCapability::Seller)
                ->count(),
            'total_listings' => $listingQuery->count(),
            'active_listings' => Listing::where('status', ListingStatus::Active)->count(),
            'sold_listings' => Listing::where('status', ListingStatus::Sold)->count(),
            'pending_listings' => Listing::where('status', ListingStatus::Pending)->count(),
            'total_transactions' => $transactionQuery->count(),
            'pending_transactions' => Transaction::where('status', TransactionStatus::Pending)
                ->when($dateFrom || $dateTo, fn ($q) => $this->applyDateFilter($q, $dateFrom, $dateTo))
                ->count(),
            'completed_transactions' => Transaction::where('status', TransactionStatus::Completed)
                ->when($dateFrom || $dateTo, fn ($q) => $this->applyDateFilter($q, $dateFrom, $dateTo))
                ->count(),
            'cancelled_transactions' => Transaction::where('status', TransactionStatus::Cancelled)
                ->when($dateFrom || $dateTo, fn ($q) => $this->applyDateFilter($q, $dateFrom, $dateTo))
                ->count(),
        ];
    }

    /**
     * Get user and seller report data.
     *
     * @return array{total: int, buyers: int, sellers: int, admins: int, registration_trend: array, seller_distribution: array}
     */
    public function getUserReport(?string $dateFrom = null, ?string $dateTo = null): array
    {
        return [
            'total' => User::count(),
            'buyers' => User::where('role', UserRole::User)
                ->where('seller_capability', SellerCapability::Buyer)
                ->count(),
            'sellers' => User::where('seller_capability', SellerCapability::Seller)
                ->count(),
            'admins' => User::where('role', UserRole::Admin)->count(),
            'registration_trend' => $this->getUserRegistrationTrend($dateFrom, $dateTo),
            'seller_distribution' => $this->getSellerDistribution(),
        ];
    }

    /**
     * Get user registration trend as monthly aggregates.
     *
     * @return array<int, array{month: string, count: int}>
     */
    private function getUserRegistrationTrend(?string $dateFrom, ?string $dateTo): array
    {
        $query = User::selectRaw("strftime('%Y-%m', created_at) as month, COUNT(*) as count")
            ->groupBy('month')
            ->orderBy('month');

        if ($dateFrom) {
            $query->where('created_at', '>=', $dateFrom);
        }
        if ($dateTo) {
            $query->where('created_at', '<=', $dateTo.' 23:59:59');
        }

        $results = $query->get();

        return $results->map(fn ($row) => [
            'month' => $row->month,
            'count' => (int) $row->count,
        ])->toArray();
    }

    /**
     * Get seller vs buyer distribution.
     *
     * @return array<int, array{label: string, count: int}>
     */
    private function getSellerDistribution(): array
    {
        return [
            ['label' => 'Buyers', 'count' => User::where('seller_capability', SellerCapability::Buyer)->count()],
            ['label' => 'Sellers', 'count' => User::where('seller_capability', SellerCapability::Seller)->count()],
        ];
    }

    /**
     * Get livestock listing report data.
     *
     * @return array{total: int, active: int, sold: int, pending: int, draft: int, inactive: int, by_type: array, by_status: array, price_stats: array}
     */
    public function getListingReport(?string $dateFrom = null, ?string $dateTo = null): array
    {
        $query = Listing::query();

        $this->applyDateFilter($query, $dateFrom, $dateTo);

        return [
            'total' => $query->count(),
            'active' => Listing::where('status', ListingStatus::Active)->count(),
            'sold' => Listing::where('status', ListingStatus::Sold)->count(),
            'pending' => Listing::where('status', ListingStatus::Pending)->count(),
            'draft' => Listing::where('status', ListingStatus::Draft)->count(),
            'inactive' => Listing::where('status', ListingStatus::Inactive)->count(),
            'by_type' => $this->getListingsByType($dateFrom, $dateTo),
            'by_status' => $this->getListingsByStatus(),
            'price_stats' => $this->getListingsPriceStats($dateFrom, $dateTo),
        ];
    }

    /**
     * Get listings grouped by livestock type.
     *
     * @return Collection<int, array{type: string, count: int}>
     */
    private function getListingsByType(?string $dateFrom, ?string $dateTo): Collection
    {
        $query = Listing::selectRaw('livestock_type as type, COUNT(*) as count')
            ->groupBy('livestock_type')
            ->orderByDesc('count');

        $this->applyDateFilter($query, $dateFrom, $dateTo);

        return $query->get();
    }

    /**
     * Get listings grouped by status.
     *
     * @return Collection<int, array{status: string, count: int}>
     */
    private function getListingsByStatus(): Collection
    {
        return Listing::selectRaw('status, COUNT(*) as count')
            ->groupBy('status')
            ->orderByDesc('count')
            ->get();
    }

    /**
     * Get price statistics for listings.
     *
     * @return array{avg_price: float, min_price: float, max_price: float, total_value: float}
     */
    private function getListingsPriceStats(?string $dateFrom, ?string $dateTo): array
    {
        $query = Listing::query();

        $this->applyDateFilter($query, $dateFrom, $dateTo);

        $stats = $query->selectRaw('AVG(asking_price) as avg_price, MIN(asking_price) as min_price, MAX(asking_price) as max_price, SUM(asking_price) as total_value')
            ->first();

        return [
            'avg_price' => (float) ($stats->avg_price ?? 0),
            'min_price' => (float) ($stats->min_price ?? 0),
            'max_price' => (float) ($stats->max_price ?? 0),
            'total_value' => (float) ($stats->total_value ?? 0),
        ];
    }

    /**
     * Get transaction report data.
     *
     * @return array{total: int, pending: int, completed: int, cancelled: int, total_revenue: float, avg_amount: float, trend: array, by_status: array, by_livestock: array}
     */
    public function getTransactionReport(?string $dateFrom = null, ?string $dateTo = null): array
    {
        $query = Transaction::query();

        $this->applyDateFilter($query, $dateFrom, $dateTo);

        $aggregates = $query->selectRaw("
            COUNT(*) as total,
            SUM(CASE WHEN status = 'pending' THEN 1 ELSE 0 END) as pending,
            SUM(CASE WHEN status = 'completed' THEN 1 ELSE 0 END) as completed,
            SUM(CASE WHEN status = 'cancelled' THEN 1 ELSE 0 END) as cancelled,
            SUM(CASE WHEN status = 'completed' THEN total_amount ELSE 0 END) as total_revenue,
            AVG(CASE WHEN status = 'completed' THEN total_amount END) as avg_amount
        ")->first();

        return [
            'total' => (int) $aggregates->total,
            'pending' => (int) $aggregates->pending,
            'completed' => (int) $aggregates->completed,
            'cancelled' => (int) $aggregates->cancelled,
            'total_revenue' => (float) ($aggregates->total_revenue ?? 0),
            'avg_amount' => (float) ($aggregates->avg_amount ?? 0),
            'trend' => $this->getTransactionTrend($dateFrom, $dateTo),
            'by_status' => $this->getTransactionsByStatus($dateFrom, $dateTo),
            'by_livestock' => $this->getTransactionsByLivestock($dateFrom, $dateTo),
        ];
    }

    /**
     * Get transaction trend over time.
     *
     * @return array<int, array{month: string, count: int, revenue: float}>
     */
    private function getTransactionTrend(?string $dateFrom, ?string $dateTo): array
    {
        $query = Transaction::selectRaw("strftime('%Y-%m', created_at) as month, COUNT(*) as count, SUM(CASE WHEN status = 'completed' THEN total_amount ELSE 0 END) as revenue")
            ->groupBy('month')
            ->orderBy('month');

        if ($dateFrom) {
            $query->where('created_at', '>=', $dateFrom);
        }
        if ($dateTo) {
            $query->where('created_at', '<=', $dateTo.' 23:59:59');
        }

        return $query->get()->map(fn ($row) => [
            'month' => $row->month,
            'count' => (int) $row->count,
            'revenue' => (float) ($row->revenue ?? 0),
        ])->toArray();
    }

    /**
     * Get transactions grouped by status.
     *
     * @return array<int, array{status: string, count: int}>
     */
    private function getTransactionsByStatus(?string $dateFrom, ?string $dateTo): array
    {
        $query = Transaction::selectRaw('status, COUNT(*) as count')
            ->groupBy('status')
            ->orderByDesc('count');

        $this->applyDateFilter($query, $dateFrom, $dateTo);

        return $query->get()->toArray();
    }

    /**
     * Get transactions grouped by livestock type.
     *
     * @return Collection<int, array{livestock_type: string, count: int, total_amount: float}>
     */
    private function getTransactionsByLivestock(?string $dateFrom, ?string $dateTo): Collection
    {
        $query = Transaction::join('listings', 'transactions.listing_id', '=', 'listings.id')
            ->selectRaw('listings.livestock_type, COUNT(*) as count, SUM(transactions.total_amount) as total_amount')
            ->groupBy('listings.livestock_type')
            ->orderByDesc('count');

        $this->applyDateFilter($query, $dateFrom, $dateTo, 'transactions');

        return $query->get();
    }

    /**
     * Get seller verification report data.
     *
     * @return array{total: int, submitted: int, pending_review: int, approved: int, rejected: int, submission_trend: array, status_distribution: array}
     */
    public function getSellerVerificationReport(?string $dateFrom = null, ?string $dateTo = null): array
    {
        $query = SellerVerification::query();

        $this->applyDateFilter($query, $dateFrom, $dateTo);

        $aggregates = $query->selectRaw("
            COUNT(*) as total,
            SUM(CASE WHEN status = 'submitted' THEN 1 ELSE 0 END) as submitted,
            SUM(CASE WHEN status = 'pending_review' THEN 1 ELSE 0 END) as pending_review,
            SUM(CASE WHEN status = 'approved' THEN 1 ELSE 0 END) as approved,
            SUM(CASE WHEN status = 'rejected' THEN 1 ELSE 0 END) as rejected
        ")->first();

        return [
            'total' => (int) $aggregates->total,
            'submitted' => (int) $aggregates->submitted,
            'pending_review' => (int) $aggregates->pending_review,
            'approved' => (int) $aggregates->approved,
            'rejected' => (int) $aggregates->rejected,
            'submission_trend' => $this->getVerificationTrend($dateFrom, $dateTo),
            'status_distribution' => $this->getVerificationStatusDistribution($dateFrom, $dateTo),
        ];
    }

    /**
     * Get verification submission trend.
     *
     * @return array<int, array{month: string, count: int}>
     */
    private function getVerificationTrend(?string $dateFrom, ?string $dateTo): array
    {
        $query = SellerVerification::selectRaw("strftime('%Y-%m', created_at) as month, COUNT(*) as count")
            ->groupBy('month')
            ->orderBy('month');

        $this->applyDateFilter($query, $dateFrom, $dateTo);

        return $query->get()->map(fn ($row) => [
            'month' => $row->month,
            'count' => (int) $row->count,
        ])->toArray();
    }

    /**
     * Get verification status distribution.
     *
     * @return array<int, array{status: string, count: int}>
     */
    private function getVerificationStatusDistribution(?string $dateFrom, ?string $dateTo): array
    {
        $query = SellerVerification::selectRaw('status, COUNT(*) as count')
            ->groupBy('status')
            ->orderByDesc('count');

        $this->applyDateFilter($query, $dateFrom, $dateTo);

        return $query->get()->toArray();
    }

    /**
     * Get activity report data.
     *
     * @return array{total: int, by_action: array, trend: array, by_user: array}
     */
    public function getActivityReport(?string $dateFrom = null, ?string $dateTo = null): array
    {
        $query = Activity::query();

        $this->applyDateFilter($query, $dateFrom, $dateTo);

        return [
            'total' => $query->count(),
            'by_action' => $this->getActivitiesByAction($dateFrom, $dateTo),
            'trend' => $this->getActivityTrend($dateFrom, $dateTo),
            'by_user' => $this->getActivitiesByUser($dateFrom, $dateTo),
        ];
    }

    /**
     * Get activities grouped by action type.
     *
     * @return Collection<int, array{action: string, count: int}>
     */
    private function getActivitiesByAction(?string $dateFrom, ?string $dateTo): Collection
    {
        $query = Activity::selectRaw('action, COUNT(*) as count')
            ->groupBy('action')
            ->orderByDesc('count');

        $this->applyDateFilter($query, $dateFrom, $dateTo);

        return $query->get();
    }

    /**
     * Get activity trend over time.
     *
     * @return array<int, array{month: string, count: int}>
     */
    private function getActivityTrend(?string $dateFrom, ?string $dateTo): array
    {
        $query = Activity::selectRaw("strftime('%Y-%m', created_at) as month, COUNT(*) as count")
            ->groupBy('month')
            ->orderBy('month');

        $this->applyDateFilter($query, $dateFrom, $dateTo);

        return $query->get()->map(fn ($row) => [
            'month' => $row->month,
            'count' => (int) $row->count,
        ])->toArray();
    }

    /**
     * Get top activities by user.
     *
     * @return Collection<int, array{user_id: int|null, user_name: string, count: int}>
     */
    private function getActivitiesByUser(?string $dateFrom, ?string $dateTo): Collection
    {
        $query = Activity::leftJoin('users', 'activities.user_id', '=', 'users.id')
            ->selectRaw('activities.user_id, COALESCE(users.name, \'System\') as user_name, COUNT(*) as count')
            ->groupBy('activities.user_id', 'users.name')
            ->orderByDesc('count')
            ->limit(10);

        $this->applyDateFilter($query, $dateFrom, $dateTo, 'activities');

        return $query->get();
    }

    /**
     * Apply date range filter to a query builder.
     *
     * @param  Builder  $query
     */
    private function applyDateFilter($query, ?string $dateFrom, ?string $dateTo, string $table = ''): void
    {
        $column = $table !== '' ? "{$table}.created_at" : 'created_at';

        if ($dateFrom !== null && $dateFrom !== '') {
            $query->where($column, '>=', $dateFrom);
        }

        if ($dateTo !== null && $dateTo !== '') {
            $query->where($column, '<=', $dateTo.' 23:59:59');
        }
    }
}
