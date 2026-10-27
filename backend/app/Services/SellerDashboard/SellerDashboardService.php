<?php

namespace App\Services\SellerDashboard;

use App\Models\User;
use App\Repositories\Inquiry\InquiryRepository;
use App\Repositories\SellerListing\SellerListingRepository;
use App\Repositories\Transaction\TransactionRepository;

/**
 * Builds the seller dashboard from the authenticated seller's own records.
 *
 * The seller is always the token's user. No summary value is selected by a
 * client-supplied id, and no revenue, conversion, or completed-transaction
 * metric is calculated here.
 */
class SellerDashboardService
{
    public function __construct(
        private readonly SellerListingRepository $listings,
        private readonly InquiryRepository $inquiries,
        private readonly TransactionRepository $transactions,
    ) {
        //
    }

    /**
     * @return array{
     *     listings: array{total: int, draft: int, pending: int, active: int, sold: int, inactive: int},
     *     inquiries: array{total: int},
     *     transactions: array{total: int, pending: int}
     * }
     */
    public function getDashboardForSeller(User $seller): array
    {
        return [
            'listings' => $this->listings->countsByStatusForSeller($seller),
            'inquiries' => [
                'total' => $this->inquiries->countForSeller($seller),
            ],
            'transactions' => $this->transactions->countsForSeller($seller),
        ];
    }
}
