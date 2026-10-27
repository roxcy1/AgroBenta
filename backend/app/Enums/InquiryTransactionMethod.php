<?php

namespace App\Enums;

/**
 * The buyer's stated preferred way to transact, carried by an inquiry.
 *
 * A preference only: selecting one does not create a transaction or change a
 * listing's status. The vocabulary is closed so the same two labels the Inquire
 * form offers are the only values the column can hold.
 */
enum InquiryTransactionMethod: string
{
    case DirectDeal = 'direct_deal';
    case ArrangeDelivery = 'arrange_delivery';

    public function label(): string
    {
        return match ($this) {
            self::DirectDeal => 'Direct Deal',
            self::ArrangeDelivery => 'Arrange Delivery',
        };
    }
}
