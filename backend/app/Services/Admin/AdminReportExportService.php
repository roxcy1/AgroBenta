<?php

namespace App\Services\Admin;

use App\Models\Activity;
use App\Models\Listing;
use App\Models\SellerVerification;
use App\Models\Transaction;
use App\Models\User;
use App\Repositories\Admin\AdminReportRepository;
use Carbon\CarbonInterface;
use Generator;

class AdminReportExportService
{
    /**
     * The datasets an administrator can download, with the CSV header each one
     * writes.
     *
     * Keeping the label and the column list together means the route's allowed
     * values, the written file and the UI selector cannot drift apart. Every
     * dataset is filtered by `created_at` in the selected range — the same
     * window the report itself applies — and the columns describe the stored
     * record, never an aggregate.
     *
     * @var array<string, array{label: string, columns: list<string>}>
     */
    public const DATASETS = [
        'transactions' => [
            'label' => 'Transactions',
            'columns' => [
                'Transaction ID',
                'Created At',
                'Status',
                'Fulfillment Status',
                'Buyer ID',
                'Buyer Name',
                'Buyer Email',
                'Seller ID',
                'Seller Name',
                'Seller Email',
                'Listing ID',
                'Livestock Type',
                'Breed',
                'Quantity',
                'Total Amount',
                'Pickup Date',
                'Payment Method',
                'Collection Method',
                'Completed At',
            ],
        ],
        'listings' => [
            'label' => 'Listings',
            'columns' => [
                'Listing ID',
                'Created At',
                'Status',
                'Seller ID',
                'Seller Name',
                'Seller Email',
                'Livestock Type',
                'Breed',
                'Gender',
                'Age Value',
                'Age Unit',
                'Weight Value',
                'Weight Unit',
                'Quantity',
                'Asking Price',
                'Location',
                'Health Status',
                'Vaccination',
                'Short Description',
            ],
        ],
        'users' => [
            'label' => 'Users',
            'columns' => [
                'User ID',
                'Registered At',
                'Name',
                'Email',
                'Role',
                'Seller Capability',
                'Email Verified At',
            ],
        ],
        'seller-verifications' => [
            'label' => 'Seller verifications',
            'columns' => [
                'Verification ID',
                'Created At',
                'Submitted At',
                'Status',
                'Seller ID',
                'Applicant Name',
                'Applicant Email',
                'Business Name',
                'Business Location',
                'Government ID Type',
                'Reviewed At',
                'Reviewer Name',
                'Admin Note',
            ],
        ],
        'activities' => [
            'label' => 'Activities',
            'columns' => [
                'Activity ID',
                'Created At',
                'Actor ID',
                'Actor Name',
                'Actor Email',
                'Action',
                'Description',
            ],
        ],
    ];

    public function __construct(private readonly AdminReportRepository $reports)
    {
        //
    }

    /**
     * Build the download filename for one dataset and range.
     *
     * The shape mirrors `buildReportExportFilename` in the Admin Web, which
     * names the browser download because the cross-origin dev API cannot expose
     * `Content-Disposition` to it. Keep both in step.
     */
    public function filename(
        string $dataset,
        ?string $dateFrom,
        ?string $dateTo,
        ?CarbonInterface $now = null,
    ): string {
        $range = match (true) {
            $dateFrom !== null && $dateTo !== null => "{$dateFrom}-to-{$dateTo}",
            $dateFrom !== null => "from-{$dateFrom}",
            $dateTo !== null => "through-{$dateTo}",
            default => 'all-time',
        };

        return sprintf(
            'agrobenta-reports-%s-%s-%s.csv',
            $dataset,
            $range,
            ($now ?? now())->format('Ymd-His'),
        );
    }

    /**
     * Write one dataset to an open stream as CSV.
     *
     * Rows are read through a lazy chunked query, so the related accounts are
     * eager loaded once per chunk instead of once per row, and an all-time
     * export is never loaded into memory. Every cell is normalised before it is
     * written.
     *
     * @param  resource  $handle
     */
    public function write(string $dataset, ?string $dateFrom, ?string $dateTo, $handle): void
    {
        fputcsv($handle, self::DATASETS[$dataset]['columns'], ',', '"', '');

        foreach ($this->rows($dataset, $dateFrom, $dateTo) as $row) {
            fputcsv($handle, array_map($this->cell(...), $row), ',', '"', '');
        }
    }

    /**
     * @return Generator<int, list<mixed>>
     */
    private function rows(string $dataset, ?string $dateFrom, ?string $dateTo): Generator
    {
        return match ($dataset) {
            'transactions' => $this->transactionRows($dateFrom, $dateTo),
            'listings' => $this->listingRows($dateFrom, $dateTo),
            'users' => $this->userRows($dateFrom, $dateTo),
            'seller-verifications' => $this->sellerVerificationRows($dateFrom, $dateTo),
            'activities' => $this->activityRows($dateFrom, $dateTo),
        };
    }

    /**
     * @return Generator<int, list<mixed>>
     */
    private function transactionRows(?string $dateFrom, ?string $dateTo): Generator
    {
        foreach ($this->reports->exportTransactions($dateFrom, $dateTo) as $transaction) {
            /** @var Transaction $transaction */
            yield [
                $transaction->id,
                $transaction->created_at?->toIso8601String(),
                $transaction->status?->value,
                $transaction->fulfillment_status?->value,
                $transaction->buyer?->id,
                $transaction->buyer?->name,
                $transaction->buyer?->email,
                $transaction->seller?->id,
                $transaction->seller?->name,
                $transaction->seller?->email,
                $transaction->listing?->id,
                $transaction->listing?->livestock_type,
                $transaction->listing?->breed,
                $transaction->quantity,
                $transaction->total_amount,
                $transaction->pickup_date?->toDateString(),
                $transaction->payment_method,
                $transaction->collection_method,
                $transaction->completed_at?->toIso8601String(),
            ];
        }
    }

    /**
     * @return Generator<int, list<mixed>>
     */
    private function listingRows(?string $dateFrom, ?string $dateTo): Generator
    {
        foreach ($this->reports->exportListings($dateFrom, $dateTo) as $listing) {
            /** @var Listing $listing */
            yield [
                $listing->id,
                $listing->created_at?->toIso8601String(),
                $listing->status?->value,
                $listing->seller?->id,
                $listing->seller?->name,
                $listing->seller?->email,
                $listing->livestock_type,
                $listing->breed,
                $listing->gender,
                $listing->age_value,
                $listing->age_unit,
                $listing->weight_value,
                $listing->weight_unit,
                $listing->quantity,
                $listing->asking_price,
                $listing->location,
                $listing->health_status,
                $listing->vaccination,
                $listing->short_description,
            ];
        }
    }

    /**
     * @return Generator<int, list<mixed>>
     */
    private function userRows(?string $dateFrom, ?string $dateTo): Generator
    {
        foreach ($this->reports->exportUsers($dateFrom, $dateTo) as $user) {
            /** @var User $user */
            yield [
                $user->id,
                $user->created_at?->toIso8601String(),
                $user->name,
                $user->email,
                $user->role?->value,
                $user->seller_capability?->value,
                $user->email_verified_at?->toIso8601String(),
            ];
        }
    }

    /**
     * @return Generator<int, list<mixed>>
     */
    private function sellerVerificationRows(?string $dateFrom, ?string $dateTo): Generator
    {
        foreach ($this->reports->exportSellerVerifications($dateFrom, $dateTo) as $verification) {
            /** @var SellerVerification $verification */
            yield [
                $verification->id,
                $verification->created_at?->toIso8601String(),
                $verification->submitted_at?->toIso8601String(),
                $verification->status?->value,
                $verification->seller?->id,
                $verification->seller?->name,
                $verification->seller?->email,
                $verification->business_name,
                $verification->business_location,
                $verification->government_id_type,
                $verification->reviewed_at?->toIso8601String(),
                $verification->reviewer?->name,
                $verification->admin_note,
            ];
        }
    }

    /**
     * @return Generator<int, list<mixed>>
     */
    private function activityRows(?string $dateFrom, ?string $dateTo): Generator
    {
        foreach ($this->reports->exportActivities($dateFrom, $dateTo) as $activity) {
            /** @var Activity $activity */
            yield [
                $activity->id,
                $activity->created_at?->toIso8601String(),
                $activity->user?->id,
                $activity->user?->name,
                $activity->user?->email,
                $activity->action,
                $activity->description,
            ];
        }
    }

    /**
     * Normalise one CSV cell.
     *
     * Numbers stay numeric so spreadsheets can total them. Text that begins
     * with a spreadsheet formula character is prefixed with an apostrophe so
     * Excel, LibreOffice and Sheets treat it as text instead of evaluating it.
     */
    private function cell(mixed $value): string|int|float
    {
        if (is_int($value) || is_float($value)) {
            return $value;
        }

        $text = $value === null ? '' : (string) $value;

        if ($text !== '' && preg_match('/^[=+\-@\t\r]/', $text) === 1) {
            return "'".$text;
        }

        return $text;
    }
}
