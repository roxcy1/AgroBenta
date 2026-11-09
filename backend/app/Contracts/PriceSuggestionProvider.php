<?php

namespace App\Contracts;

use App\Data\PriceSuggestionInput;
use App\Data\PriceSuggestionResult;

/**
 * The Laravel-facing boundary for an external price estimator.
 *
 * Laravel never depends on CatBoost, .cbm filenames, or the model host's
 * internals. Any compatible provider can be swapped by binding this interface.
 */
interface PriceSuggestionProvider
{
    /**
     * Return a point estimate, or throw a structured domain exception.
     */
    public function predict(PriceSuggestionInput $input): PriceSuggestionResult;
}
