<?php

namespace App\Enums;

/**
 * How the buyer prefers to be contacted about an inquiry.
 *
 * In-app messaging is the only approved channel, so it is the only case. The
 * enum exists (rather than a free string) so a future channel is an explicit
 * decision rather than an accepted value.
 */
enum InquiryContactMethod: string
{
    case InAppMessage = 'in_app_message';

    public function label(): string
    {
        return match ($this) {
            self::InAppMessage => 'In-app message',
        };
    }
}
