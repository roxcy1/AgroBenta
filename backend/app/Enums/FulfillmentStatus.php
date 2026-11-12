<?php

namespace App\Enums;

use App\Models\Transaction;

/**
 * The physical fulfillment stage of a transaction.
 *
 * This is deliberately separate from {@see TransactionStatus}: the ERD's
 * three-value lifecycle still records whether the sale is pending, completed or
 * cancelled, while this progression records what the seller and buyer have
 * agreed has happened on the ground.
 *
 * Pickup flows (personal pickup, buyer-arranged transportation, legacy/unknown
 * methods) use `ready_for_pickup` and `picked_up`. Seller-arranged delivery uses
 * `on_the_way` and `delivered`. Both end with the buyer confirming receipt.
 */
enum FulfillmentStatus: string
{
    case Confirmed = 'confirmed';
    case Preparing = 'preparing';
    case ReadyForPickup = 'ready_for_pickup';
    case PickedUp = 'picked_up';
    case OnTheWay = 'on_the_way';
    case Delivered = 'delivered';
    case Completed = 'completed';

    public const FLOW_PICKUP = 'pickup';

    public const FLOW_DELIVERY = 'delivery';

    public function label(): string
    {
        return match ($this) {
            self::Confirmed => 'Confirmed',
            self::Preparing => 'Preparing',
            self::ReadyForPickup => 'Ready for pickup',
            self::PickedUp => 'Picked up',
            self::OnTheWay => 'On the way',
            self::Delivered => 'Delivered',
            self::Completed => 'Completed',
        };
    }

    /**
     * Which progression the transaction follows.
     *
     * Only an explicit `seller_arranged_delivery` uses the delivery stages.
     * Buyer-arranged transportation, personal pickup, "not sure yet", the legacy
     * `discuss_with_seller` value and a null collection method all use the
     * pickup/handover stages, which is the safer default because handover is
     * explicit.
     */
    public static function flowFor(?string $collectionMethod): string
    {
        return $collectionMethod === InquiryCollectionMethod::SellerArrangedDelivery->value
            ? self::FLOW_DELIVERY
            : self::FLOW_PICKUP;
    }

    /**
     * The next stage the seller may move to, or null when only the buyer can
     * act (or the progression is finished).
     */
    public function nextSellerStatus(string $flow): ?self
    {
        return match ($flow) {
            self::FLOW_PICKUP => match ($this) {
                self::Confirmed => self::Preparing,
                self::Preparing => self::ReadyForPickup,
                self::ReadyForPickup => self::PickedUp,
                default => null,
            },
            self::FLOW_DELIVERY => match ($this) {
                self::Confirmed => self::Preparing,
                self::Preparing => self::OnTheWay,
                self::OnTheWay => self::Delivered,
                default => null,
            },
            default => null,
        };
    }

    /**
     * The API action name that moves the seller to [target].
     */
    public static function actionFor(self $target): string
    {
        return match ($target) {
            self::Preparing => 'preparing',
            self::ReadyForPickup => 'ready_for_pickup',
            self::PickedUp => 'picked_up',
            self::OnTheWay => 'on_the_way',
            self::Delivered => 'delivered',
            default => $target->value,
        };
    }

    /**
     * Whether either party may still cancel at this stage.
     *
     * Delivery stops being cancellable once the seller dispatches; pickup stops
     * once the livestock has been handed over.
     */
    public function allowsCancellation(string $flow): bool
    {
        return match ($flow) {
            self::FLOW_PICKUP => in_array($this, [
                self::Confirmed,
                self::Preparing,
                self::ReadyForPickup,
            ], true),
            self::FLOW_DELIVERY => in_array($this, [
                self::Confirmed,
                self::Preparing,
            ], true),
            default => false,
        };
    }

    /**
     * Whether the buyer may confirm receipt at this stage.
     */
    public function canBeConfirmedReceived(string $flow): bool
    {
        return match ($flow) {
            self::FLOW_PICKUP => $this === self::PickedUp,
            self::FLOW_DELIVERY => $this === self::Delivered,
            default => false,
        };
    }

    /**
     * Everything the viewer may do to a pending transaction, in the order the
     * mobile screen should offer it.
     *
     * @return list<string>
     */
    public static function permittedActionsFor(Transaction $transaction, ?int $viewerId): array
    {
        if ($viewerId === null ||
            $transaction->status !== TransactionStatus::Pending) {
            return [];
        }

        $flow = self::flowFor($transaction->collection_method);
        $current = $transaction->fulfillment_status ?? self::Confirmed;
        $isSeller = (int) $transaction->seller_id === $viewerId;
        $isBuyer = (int) $transaction->buyer_id === $viewerId;

        if (! $isSeller && ! $isBuyer) {
            return [];
        }

        $actions = [];

        if ($isSeller) {
            $next = $current->nextSellerStatus($flow);
            if ($next !== null) {
                $actions[] = self::actionFor($next);
            }
        }

        if ($isBuyer && $current->canBeConfirmedReceived($flow)) {
            $actions[] = 'confirm_received';
        }

        if ($current->allowsCancellation($flow)) {
            $actions[] = 'cancel';
        }

        return $actions;
    }
}
