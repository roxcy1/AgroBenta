<?php

namespace App\Services\Transaction;

use App\Enums\TransactionStatus;
use App\Models\Transaction;
use App\Models\User;
use App\Repositories\Transaction\TransactionRepository;
use Carbon\CarbonInterface;

/**
 * Reads and freezes the receipt projection of a completed transaction.
 *
 * The snapshot is written in the same database transaction as completion, so a
 * completed row and its receipt cannot disagree. Only receipt-safe values are
 * copied: names, listing identity, quantity, agreed total and the recorded
 * preferences. Emails, contact details and photos stay out of the document.
 */
class TransactionReceiptService
{
    public function __construct(
        private readonly TransactionRepository $transactions,
    ) {}

    /**
     * Build the immutable snapshot stored on the transaction.
     *
     * @return array<string, mixed>
     */
    public function snapshot(Transaction $transaction, CarbonInterface $completedAt): array
    {
        $transaction->loadMissing([
            'buyer:id,name',
            'seller:id,name',
            'listing:id,livestock_type,breed',
        ]);

        return [
            'version' => 1,
            'reference' => $transaction->receiptReference(),
            'completed_at' => $completedAt->toISOString(),
            'buyer' => [
                'name' => (string) $transaction->buyer?->name,
            ],
            'seller' => [
                'name' => (string) $transaction->seller?->name,
            ],
            'listing' => [
                'livestock_type' => (string) $transaction->listing?->livestock_type,
                'breed' => (string) ($transaction->listing?->breed ?? ''),
            ],
            'quantity' => (int) $transaction->quantity,
            'total_amount' => (string) $transaction->total_amount,
            'payment_method' => $transaction->payment_method,
            'collection_method' => $transaction->collection_method,
            'status' => TransactionStatus::Completed->value,
        ];
    }

    /**
     * Find a completed transaction the caller is a party to.
     *
     * A non-party and a missing record are the same 404; a pending or cancelled
     * record is a 409 because it exists but has no receipt.
     */
    public function forUser(int $transactionId, User $user): Transaction
    {
        $transaction = $this->transactions->findForUser($transactionId, $user);

        if ($transaction === null) {
            abort(404, 'Transaction not found.');
        }

        if ($transaction->status !== TransactionStatus::Completed) {
            abort(409, 'Only a completed transaction has a receipt.');
        }

        return $transaction;
    }
}
