<?php

namespace App\Enums;

/**
 * The buyer's stated preferred way to pay the seller, carried by an inquiry.
 *
 * A preference only: selecting one does not create a payment, and the server
 * does not process any payment. The vocabulary is closed so the same four
 * labels the Inquire form offers are the only values the column can hold.
 * `other` is the "Other / Discuss with seller" option.
 */
enum InquiryPaymentMethod: string
{
    case Cash = 'cash';
    case Gcash = 'gcash';
    case Maya = 'maya';
    case Other = 'other';

    public function label(): string
    {
        return match ($this) {
            self::Cash => 'Cash',
            self::Gcash => 'GCash',
            self::Maya => 'Maya',
            self::Other => 'Other / Discuss with seller',
        };
    }
}
