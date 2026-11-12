<?php

namespace App\Enums;

/**
 * Whether a listing's weight was measured or estimated by the seller.
 *
 * The value is persisted as a short string and exposed by the listing
 * resources. Historical rows may predate the selector and store `null`; they
 * are never rewritten automatically.
 */
enum WeightInformation: string
{
    case Measured = 'measured';
    case Estimated = 'estimated';
}
