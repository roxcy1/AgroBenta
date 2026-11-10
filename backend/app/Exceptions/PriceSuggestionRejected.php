<?php

namespace App\Exceptions;

use RuntimeException;

/**
 * A safe, structured refusal: invalid local input, draft-only violation, an
 * unsupported breed, or a withheld provider prediction. Nothing is persisted.
 */
class PriceSuggestionRejected extends RuntimeException
{
    /**
     * @param  list<string>  $reasonCodes
     * @param  list<string>  $warnings
     */
    public function __construct(
        public readonly string $status,
        public readonly array $reasonCodes,
        public readonly array $warnings,
        string $message = 'A price suggestion cannot be generated for this listing.',
    ) {
        parent::__construct($message);
    }
}
