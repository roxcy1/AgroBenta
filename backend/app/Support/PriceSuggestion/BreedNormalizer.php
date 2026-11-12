<?php

namespace App\Support\PriceSuggestion;

use App\Enums\LivestockType;
use Illuminate\Support\Str;

/**
 * Normalize the free-text listing breed to the provider's canonical vocabulary.
 *
 * The canonical provider lists live on [LivestockType::canonicalBreeds()],
 * which mirrors ml-service/features.py. The public catalog may use readable
 * breed names, so both names are normalized to the provider's stable slugs.
 * An unknown value is rejected rather than guessed.
 */
final class BreedNormalizer
{
    /**
     * Explicit aliases for common seller spellings. Values not listed here are
     * accepted only when their slug is already canonical.
     *
     * @var array<string, string>
     */
    private const ALIASES = [
        'brahman_x' => 'brahman_cross',
        'brahman_mix' => 'brahman_cross',
        'holstein' => 'holstein_friesian',
        'friesian' => 'holstein_friesian',
        'native_cattle' => 'philippine_native_cattle',
        'murrah_cross' => 'native_murrah_cross',
        'native_carabao' => 'philippine_native_carabao',
        'anglo_nubian_goat' => 'anglo_nubian',
        'boholano_native_goat' => 'ubay_boholano_native_goat',
        'duroc_cross' => 'duroc_landrace_cross',
        'landrace_cross' => 'duroc_landrace_cross',
        'large_white' => 'large_white_yorkshire',
        'yorkshire' => 'large_white_yorkshire',
        'nativemurrah_cross' => 'native_murrah_cross',
        'ubayboholano_native_goat' => 'ubay_boholano_native_goat',
        'duroclandrace_cross' => 'duroc_landrace_cross',
        'boholano_native' => 'boholano_native_chicken',
        'improved_native' => 'improved_native_chicken',
        'broiler_chicken' => 'broiler',
        'layer_chicken' => 'layer',
    ];

    public static function normalize(?string $breed, string $livestockType): ?string
    {
        if ($breed === null || trim($breed) === '') {
            return null;
        }

        $category = strtolower(trim($livestockType));
        $canonical = LivestockType::tryFrom($category)?->canonicalBreeds() ?? [];
        $slug = Str::slug($breed, '_');
        $candidate = self::ALIASES[$slug] ?? $slug;

        return in_array($candidate, $canonical, true) ? $candidate : null;
    }
}
