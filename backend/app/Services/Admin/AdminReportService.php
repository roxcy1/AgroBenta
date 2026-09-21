<?php

namespace App\Services\Admin;

use App\Repositories\Admin\AdminReportRepository;

class AdminReportService
{
    public function __construct(private readonly AdminReportRepository $reports)
    {
        //
    }

    /**
     * Get all report sections with optional date filtering.
     *
     * @return array{overview: array, users: array, listings: array, transactions: array, seller_verifications: array, activities: array}
     */
    public function getReports(?string $dateFrom = null, ?string $dateTo = null): array
    {
        return [
            'overview' => $this->reports->getMarketplaceOverview($dateFrom, $dateTo),
            'users' => $this->reports->getUserReport($dateFrom, $dateTo),
            'listings' => $this->reports->getListingReport($dateFrom, $dateTo),
            'transactions' => $this->reports->getTransactionReport($dateFrom, $dateTo),
            'seller_verifications' => $this->reports->getSellerVerificationReport($dateFrom, $dateTo),
            'activities' => $this->reports->getActivityReport($dateFrom, $dateTo),
        ];
    }
}
