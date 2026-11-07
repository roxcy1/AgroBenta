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
            self::Carabao => 'Carabao',
            self::Cattle => 'Cattle',
            self::Goat => 'Goat',
            self::Swine => 'Swine',
            self::Chicken => 'Chicken',
        };
    }

    /**
     * The approved breed names for this livestock category.
     *
     * @return list<string>
     */
    public function breeds(): array
    {
        return match ($this) {
            self::Carabao => [
                'Philippine Native Carabao',
                'Murrah',
                'Native–Murrah Cross',
            ],
            self::Cattle => [
                'Philippine Native Cattle',
                'Brahman',
                'Holstein Friesian',
                'Brahman Cross',
            ],
            self::Goat => [
                'Ubay/Boholano Native Goat',
                'Boer',
                'Anglo-Nubian',
                'Saanen',
            ],
            self::Swine => [
                'Native Pig',
                'Landrace',
                'Large White (Yorkshire)',
                'Duroc',
                'Duroc–Landrace Cross',
            ],
            self::Chicken => [
                'Boholano Native Chicken',
                'Broiler',
                'Layer',
                'Improved Native Chicken',
            ],
        };
    }

    public function hasBreed(string $breed): bool
    {
        return in_array(trim($breed), $this->breeds(), true);
    }

    public static function isCatalogBreed(string $breed): bool
    {
        foreach (self::cases() as $type) {
            if ($type->hasBreed($breed)) {
                return true;
            }
        }

        return false;
    }

    /**
     * The client-facing catalog, in display order.
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
