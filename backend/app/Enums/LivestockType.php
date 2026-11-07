<?php

namespace App\Enums;

/**
 * The approved livestock categories for new and updated listings.
 *
 * Historical rows may still contain values outside this enum. They are kept
 * readable on purpose and are never normalized by the application.
 */
enum LivestockType: string
{
    case Cattle = 'cattle';
    case Carabao = 'carabao';
    case Goat = 'goat';
    case Swine = 'swine';
    case Chicken = 'chicken';

    public function label(): string
    {
        return match ($this) {
            self::Cattle => 'Cattle',
            self::Carabao => 'Carabao',
            self::Goat => 'Goat',
            self::Swine => 'Swine',
            self::Chicken => 'Chicken',
        };
    }

    /**
     * The canonical breeds the price-suggestion provider accepts for this type.
     *
     * This mirrors `ml-service/features.py`. Keeping the vocabulary on the enum
     * makes the catalog and the Laravel-side normalizer read from one place.
     *
     * @return list<string>
     */
    public function breeds(): array
    {
        return match ($this) {
            self::Cattle => [
                'brahman',
                'brahman_cross',
                'holstein_friesian',
                'philippine_native_cattle',
            ],
            self::Carabao => [
                'murrah',
                'native_murrah_cross',
                'philippine_native_carabao',
            ],
            self::Goat => [
                'anglo_nubian',
                'boer',
                'saanen',
                'ubay_boholano_native_goat',
            ],
            self::Swine => [
                'duroc',
                'duroc_landrace_cross',
                'landrace',
                'large_white_yorkshire',
                'native_pig',
            ],
            self::Chicken => [
                'boholano_native_chicken',
                'broiler',
                'improved_native_chicken',
                'layer',
            ],
        };
    }

    /**
     * The client-facing catalog, in display order.
     *
     * `breeds` is the controlled vocabulary the model accepts for the category.
     * Clients may use it as a selector but are not required to; the listing
     * `breed` column itself stays free text so historical rows remain readable.
     *
     * @return list<array{value: string, label: string, breeds: list<string>}>
     */
    public static function options(): array
    {
        return array_map(
            static fn (self $type): array => [
                'value' => $type->value,
                'label' => $type->label(),
                'breeds' => $type->breeds(),
            ],
            self::cases(),
        );
    }
}
