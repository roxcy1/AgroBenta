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

    public function label(): string
    {
        return match ($this) {
            self::Cattle => 'Cattle',
            self::Carabao => 'Carabao',
            self::Goat => 'Goat',
            self::Swine => 'Swine',
        };
    }

    /**
     * The client-facing catalog, in display order.
     *
     * @return list<array{value: string, label: string}>
     */
    public static function options(): array
    {
        return array_map(
            static fn (self $type): array => [
                'value' => $type->value,
                'label' => $type->label(),
            ],
            self::cases(),
        );
    }
}
