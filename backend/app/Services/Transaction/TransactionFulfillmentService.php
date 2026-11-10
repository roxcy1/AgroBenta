<?php

namespace App\Services\Transaction;

use App\Enums\ActivityAction;
use App\Enums\FulfillmentStatus;
use App\Enums\TransactionStatus;
use App\Events\TransactionUpdated;
use App\Models\Transaction;
use App\Models\User;
use App\Notifications\TransactionFulfillmentChanged;
use App\Notifications\TransactionStatusChanged;
use App\Repositories\Transaction\TransactionRepository;
use App\Services\ActivityLogger;
use App\Services\Listing\ListingReservationService;
use Illuminate\Support\Facades\DB;

/**
 * The seller/buyer fulfillment progression for one transaction.
 *
 * Every action takes the transaction row lock first, re-checks the persisted
 * status and stage, and writes the new stage inside the same database
 * transaction. The separate `transactions.status` remains the ERD lifecycle:
 * only the buyer's receipt confirmation moves it to `completed`.
 *
 * The progression depends on the collection method:
 *
 *  - pickup / buyer-arranged / unknown: confirmed -> preparing ->
 *    ready_for_pickup -> picked_up -> completed
 *  - seller-arranged delivery: confirmed -> preparing -> on_the_way ->
 *    delivered -> completed
 *
 * A seller action not valid for the transaction's flow is a 409, not a silent
 * status write. Cancellation cutoffs and the legacy-stock policy live here and
 * in {@see TransactionService::cancel()}.
 */
class TransactionFulfillmentService
{
    public function __construct(
        private readonly TransactionRepository $transactions,
        private readonly ListingReservationService $reservations,
        private readonly ActivityLogger $activity,
    ) {
        //
    }

    /**
     * Start preparing: confirmed -> preparing for both flows.
     */
    public function markPreparing(int $transactionId, User $seller): Transaction
    {
        return $this->sellerTransition($transactionId, $seller, FulfillmentStatus::Preparing);
    }

    /**
     * Pickup only: preparing -> ready_for_pickup.
     */
    public function markReadyForPickup(int $transactionId, User $seller): Transaction
    {
        return $this->sellerTransition($transactionId, $seller, FulfillmentStatus::ReadyForPickup);
    }

    /**
     * Pickup only: ready_for_pickup -> picked_up.
     */
    public function confirmHandover(int $transactionId, User $seller): Transaction
    {
        return $this->sellerTransition($transactionId, $seller, FulfillmentStatus::PickedUp);
    }

    /**
     * Delivery only: preparing -> on_the_way.
     */
    public function markOnTheWay(int $transactionId, User $seller): Transaction
    {
        return $this->sellerTransition($transactionId, $seller, FulfillmentStatus::OnTheWay);
    }

    /**
     * Delivery only: on_the_way -> delivered.
     */
    public function markDelivered(int $transactionId, User $seller): Transaction
    {
        return $this->sellerTransition($transactionId, $seller, FulfillmentStatus::Delivered);
    }

    /**
     * Buyer confirms receipt after pickup or delivery and completes the sale.
     */
    public function confirmReceived(int $transactionId, User $buyer): Transaction
    {
        return DB::transaction(function () use ($transactionId, $buyer): Transaction {
            $locked = $this->transactions->lockForUser($transactionId, $buyer);

            if ($locked === null) {
                abort(404, 'Transaction not found.');
            }

            if ($locked->status !== TransactionStatus::Pending) {
                abort(409, 'Only a pending transaction can be completed.');
            }

            if ((int) $locked->buyer_id !== (int) $buyer->getKey()) {
                abort(409, 'Only the buyer may confirm receipt.');
            }

            $flow = FulfillmentStatus::flowFor($locked->collection_method);
            $current = $locked->fulfillment_status ?? FulfillmentStatus::Confirmed;

            if (! $current->canBeConfirmedReceived($flow)) {
                abort(409, 'Receipt can only be confirmed after pickup or delivery.');
            }

            // Historical rows predate reservation. Take the stock now so a
            // legacy sale cannot complete without holding its quantity; if the
            // listing has no stock left, the completion is refused.
            if (! $locked->inventory_reserved) {
                $this->reservations->reserve(
                    (int) $locked->listing_id,
                    (int) $locked->quantity,
                );
                $locked = $this->transactions->markInventoryReserved($locked);
            }

            $completed = $this->transactions->complete($locked);

            $this->activity->log(
                $buyer,
                ActivityAction::TransactionCompleted,
                sprintf('Transaction #%d completed.', $completed->getKey()),
                [
                    'target_type' => 'transaction',
                    'target_id' => $completed->getKey(),
                    'context' => [
                        'listing_id' => $completed->listing_id,
                        'buyer_id' => $completed->buyer_id,
                        'seller_id' => $completed->seller_id,
                    ],
                    'changes' => [
                        'status' => [
                            'from' => TransactionStatus::Pending->value,
                            'to' => TransactionStatus::Completed->value,
                        ],
                        'fulfillment_status' => [
                            'from' => $current->value,
                            'to' => FulfillmentStatus::Completed->value,
                        ],
                    ],
                ],
            );

            $seller = User::find((int) $completed->seller_id);
            if ($seller !== null) {
                $seller->notify(new TransactionStatusChanged(
                    $completed->fresh(['listing']),
                    $buyer->getKey(),
                    TransactionStatus::Pending->value,
                    TransactionStatus::Completed->value,
                ));
            }

            TransactionUpdated::dispatch(
                $completed,
                TransactionStatus::Completed->value,
                FulfillmentStatus::Completed->value,
                (int) $completed->seller_id,
            );

            return $completed;
        });
    }

    /**
     * Apply one seller-controlled stage with the row lock held.
     */
    private function sellerTransition(
        int $transactionId,
        User $seller,
        FulfillmentStatus $target,
    ): Transaction {
        return DB::transaction(function () use ($transactionId, $seller, $target): Transaction {
            $locked = $this->transactions->lockForUser($transactionId, $seller);

            if ($locked === null) {
                abort(404, 'Transaction not found.');
            }

            if ($locked->status !== TransactionStatus::Pending) {
                abort(409, 'Only a pending transaction can be updated.');
            }

            if ((int) $locked->seller_id !== (int) $seller->getKey()) {
                abort(409, 'Only the seller may update fulfillment.');
            }

            $flow = FulfillmentStatus::flowFor($locked->collection_method);
            $current = $locked->fulfillment_status ?? FulfillmentStatus::Confirmed;

            if ($current->nextSellerStatus($flow) !== $target) {
                abort(409, 'This fulfillment step is not available for this transaction.');
            }

            $updated = $this->transactions->updateFulfillmentStatus($locked, $target);

            $this->activity->log(
                $seller,
                ActivityAction::TransactionFulfillmentUpdated,
                sprintf(
                    'Transaction #%d fulfillment moved to %s.',
                    $updated->getKey(),
                    $target->value,
                ),
                [
                    'target_type' => 'transaction',
                    'target_id' => $updated->getKey(),
                    'context' => [
                        'listing_id' => $updated->listing_id,
                        'buyer_id' => $updated->buyer_id,
                        'seller_id' => $updated->seller_id,
                    ],
                    'changes' => [
                        'fulfillment_status' => [
                            'from' => $current->value,
                            'to' => $target->value,
                        ],
                    ],
                ],
            );

            $buyer = User::find((int) $updated->buyer_id);
            if ($buyer !== null) {
                $buyer->notify(new TransactionFulfillmentChanged(
                    $updated->fresh(['listing', 'buyer', 'seller']),
                    $seller->getKey(),
                    $current,
                    $target,
                ));
            }

            TransactionUpdated::dispatch(
                $updated,
                TransactionStatus::Pending->value,
                $target->value,
                (int) $updated->buyer_id,
            );

            return $updated;
        });
    }
}
