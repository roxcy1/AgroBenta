<?php

namespace App\Exceptions;

use RuntimeException;

/**
 * The provider could not be reached, timed out, returned an incompatible
 * contract, or otherwise failed safely. No estimate is persisted.
 */
class PriceSuggestionUnavailable extends RuntimeException
{
    public function __construct(
        string $message = 'The price suggestion service is unavailable.',
    ) {
        parent::__construct($message);
    }
}
