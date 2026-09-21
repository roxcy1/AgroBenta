<?php

namespace App\Services;

use App\Enums\ListingStatus;
use App\Enums\SellerCapability;
use App\Enums\TransactionStatus;
use App\Enums\UserRole;
use App\Models\Activity;
use App\Models\Listing;
use App\Models\Transaction;
use App\Models\User;
use Illuminate\Support\Carbon;
use Illuminate\Support\Collection;

class DashboardService
{
    /**
     * Get the complete dashboard data.
     *
     * @return array{summary: array, listings: array, transactions: array, transaction_trend: array, livestock_distribution: array, recent_activities: array}
     */
    public function getDashboardData(): array
    {
        return [
            'summary' => $this->getSummary(),
            'listings' => $this->getListingsData(),
            'transactions' => $this->getTransactionsData(),
            'transaction_trend' => $this->getTransactionTrend(),
            'livestock_distribution' => $this->getLivestockDistribution(),
            'recent_activities' => $this->getRecentActivities(),
        ];
    }

    /**
     * Get summary statistics for users, listings, and transactions.
     */
    private function getSummary(): array
    {
        return [
            'total_users' => User::count(),
            'buyer_accounts' => User::where('role', UserRole::User)
                ->where('seller_capability', SellerCapability::Buyer)
                ->count(),
            'approved_sellers' => User::where('seller_capability', SellerCapability::Seller)
                ->count(),
            'total_listings' => Listing::count(),
            'active_listings' => Listing::where('status', ListingStatus::Active)->count(),
            'total_transactions' => Transaction::count(),
        ];
    }

    /**
     * Get detailed listing statistics.
     */
    private function getListingsData(): array
    {
        return [
            'total' => Listing::count(),
            'active' => Listing::where('status', ListingStatus::Active)->count(),
            'sold' => Listing::where('status', ListingStatus::Sold)->count(),
            'pending' => Listing::where('status', ListingStatus::Pending)->count(),
            'draft' => Listing::where('status', ListingStatus::Draft)->count(),
            'inactive' => Listing::where('status', ListingStatus::Inactive)->count(),
        ];
    }

    /**
     * Get detailed transaction statistics.
     */
    private function getTransactionsData(): array
    {
        return [
            'total' => Transaction::count(),
            'pending' => Transaction::where('status', TransactionStatus::Pending)->count(),
            'completed' => Transaction::where('status', TransactionStatus::Completed)->count(),
            'cancelled' => Transaction::where('status', TransactionStatus::Cancelled)->count(),
        ];
    }

    /**
     * Get transaction trend data for the current year (monthly aggregation).
     *
     * @return array<int, array{month: string, count: number, revenue: number}>
     */
    private function getTransactionTrend(): array
    {
        $year = Carbon::now()->year;
        $startOfYear = Carbon::create($year, 1, 1)->startOfMonth();
        $endOfYear = Carbon::create($year, 12, 31)->endOfMonth();

        $transactions = Transaction::whereBetween('created_at', [$startOfYear, $endOfYear])
            ->select('created_at', 'total_amount', 'status')
            ->get()
            ->groupBy(fn (Transaction $t) => $t->created_at->month);

        $monthlyData = [];
        for ($m = 1; $m <= 12; $m++) {
            $monthName = Carbon::create($year, $m, 1)->format('M');
            $monthTransactions = $transactions->get($m, collect());

            $totalForMonth = $monthTransactions->count();
            $completedRevenue = $monthTransactions
                ->where('status', TransactionStatus::Completed)
                ->sum('total_amount');

            $monthlyData[] = [
                'month' => $monthName,
                'count' => (int) $totalForMonth,
                'revenue' => (float) $completedRevenue,
            ];
        }

        return $monthlyData;
    }

    /**
     * Get livestock distribution by type from actual listings.
     *
     * @return Collection<int, array{type: string, count: number}>
     */
    private function getLivestockDistribution(): Collection
    {
        return Listing::selectRaw('livestock_type as type, COUNT(*) as count')
            ->groupBy('livestock_type')
            ->orderByDesc('count')
            ->get();
    }

    /**
     * Get the most recent activities.
     *
     * @return Collection<int, Activity>
     */
    private function getRecentActivities(): Collection
    {
        return Activity::with('user:id,name')
            ->orderByDesc('created_at')
            ->limit(10)
            ->get();
    }
}
