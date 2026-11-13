<?php

namespace App\Enums;

/**
 * The lifecycle state of a purchase offer made by a seller to a buyer
 * within a buyer–seller conversation.
 *
 * `pending` is the only actionable state: the buyer may accept or decline,
 * and the seller may withdraw. `accepted`, `declined`, `withdrawn` and
 * `expired` are terminal — an offer never moves out of them.
 */
enum OfferStatus: string
{
    case Pending = 'pending';
    case Accepted = 'accepted';
    case Declined = 'declined';
    case Withdrawn = 'withdrawn';
    case Expired = 'expired';

    public function label(): string
    {
        return match ($this) {
            self::Pending => 'Pending',
            self::Accepted => 'Accepted',
            self::Declined => 'Declined',
            self::Withdrawn => 'Withdrawn',
            self::Expired => 'Expired',
        };
    }
}
