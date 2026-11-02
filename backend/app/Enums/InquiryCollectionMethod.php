<?php

namespace App\Enums;

/**
 * The buyer's stated preferred way to receive the livestock, carried by an
 * inquiry.
 *
 * A preference only: selecting one does not book transportation and AgroBenta
 * does not provide, book, or track riders. The vocabulary is closed so the
 * same three labels the Inquire form offers are the only values the column can
 * hold. `discussWithSeller` is the "Discuss arrangements with the seller"
 * option.
 */
enum InquiryCollectionMethod: string
{
    case FarmPickup = 'farm_pickup';
    case BuyerArrangedTransportation = 'buyer_arranged_transportation';
    case DiscussWithSeller = 'discuss_with_seller';

    public function label(): string
    {
        return match ($this) {
            self::FarmPickup => 'Pick up from the seller\'s farm',
            self::BuyerArrangedTransportation => 'Arrange my own livestock transportation',
            self::DiscussWithSeller => 'Discuss arrangements with the seller',
        };
    }
}
