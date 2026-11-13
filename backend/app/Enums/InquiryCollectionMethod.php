<?php

namespace App\Enums;

/**
 * The buyer's stated preferred way to receive the livestock, carried by an
 * inquiry.
 *
 * A preference only: selecting one does not book transportation and AgroBenta
 * does not provide, book, or track riders. `DiscussWithSeller` is retained only
 * so historical inquiry records still cast and render; it is not offered by the
 * current Inquire form. New inquiries use one of the four approved choices.
 */
enum InquiryCollectionMethod: string
{
    case FarmPickup = 'farm_pickup';
    case BuyerArrangedTransportation = 'buyer_arranged_transportation';
    case SellerArrangedDelivery = 'seller_arranged_delivery';
    case NotSureYet = 'not_sure_yet';

    /**
     * Legacy value retained for existing records. It is deliberately not a
     * current form option.
     */
    case DiscussWithSeller = 'discuss_with_seller';

    public function label(): string
    {
        return match ($this) {
            self::FarmPickup => 'Pick up from the seller\'s farm',
            self::BuyerArrangedTransportation => 'Arrange my own livestock transportation',
            self::SellerArrangedDelivery => 'Seller-arranged delivery',
            self::NotSureYet => 'Not sure yet',
            self::DiscussWithSeller => 'Discuss arrangements with the seller (legacy)',
        };
    }

    /**
     * The values the current mobile form may submit.
     *
     * @return list<string>
     */
    public static function selectableValues(): array
    {
        return [
            self::FarmPickup->value,
            self::BuyerArrangedTransportation->value,
            self::SellerArrangedDelivery->value,
            self::NotSureYet->value,
        ];
    }
}
