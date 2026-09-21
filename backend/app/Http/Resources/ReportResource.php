<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class ReportResource extends JsonResource
{
    /**
     * Transform the report data into a structured API response.
     *
     * @return array<string, mixed>
     */
    public function toArray(Request $request): array
    {
        return [
            'overview' => $this->resource['overview'],
            'users' => $this->formatUserReport($this->resource['users']),
            'listings' => $this->formatListingReport($this->resource['listings']),
            'transactions' => $this->formatTransactionReport($this->resource['transactions']),
            'seller_verifications' => $this->formatVerificationReport($this->resource['seller_verifications']),
            'activities' => $this->formatActivityReport($this->resource['activities']),
        ];
    }

    private function formatUserReport(array $data): array
    {
        return [
            'total' => $data['total'],
            'buyers' => $data['buyers'],
            'sellers' => $data['sellers'],
            'admins' => $data['admins'],
            'registration_trend' => $data['registration_trend'],
            'seller_distribution' => $data['seller_distribution'],
        ];
    }

    private function formatListingReport(array $data): array
    {
        return [
            'total' => $data['total'],
            'active' => $data['active'],
            'sold' => $data['sold'],
            'pending' => $data['pending'],
            'draft' => $data['draft'],
            'inactive' => $data['inactive'],
            'by_type' => $data['by_type'],
            'by_status' => $data['by_status'],
            'price_stats' => $data['price_stats'],
        ];
    }

    private function formatTransactionReport(array $data): array
    {
        return [
            'total' => $data['total'],
            'pending' => $data['pending'],
            'completed' => $data['completed'],
            'cancelled' => $data['cancelled'],
            'total_revenue' => $data['total_revenue'],
            'avg_amount' => $data['avg_amount'],
            'trend' => $data['trend'],
            'by_status' => $data['by_status'],
            'by_livestock' => $data['by_livestock'],
        ];
    }

    private function formatVerificationReport(array $data): array
    {
        return [
            'total' => $data['total'],
            'submitted' => $data['submitted'],
            'pending_review' => $data['pending_review'],
            'approved' => $data['approved'],
            'rejected' => $data['rejected'],
            'submission_trend' => $data['submission_trend'],
            'status_distribution' => $data['status_distribution'],
        ];
    }

    private function formatActivityReport(array $data): array
    {
        return [
            'total' => $data['total'],
            'by_action' => $data['by_action'],
            'trend' => $data['trend'],
            'by_user' => $data['by_user'],
        ];
    }
}
