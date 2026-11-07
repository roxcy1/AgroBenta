<?php

namespace App\Support;

use App\Enums\TrinidadBarangay;

/** Formats and parses the existing string-backed Trinidad location fields. */
final class TrinidadLocationAddress
{
    public const string MUNICIPALITY = 'Trinidad';

    public const string PROVINCE = 'Bohol';

    public const string REGION = 'Central Visayas (Region VII)';

    public static function format(string $barangay, ?string $street = null): string
    {
        $name = TrinidadBarangay::tryFrom(trim($barangay))?->value;
        if ($name === null) {
            throw new \InvalidArgumentException('A supported Trinidad barangay is required.');
        }

        $parts = [];
        $street = trim((string) $street);
        if ($street !== '') {
            $parts[] = $street;
        }

        $parts[] = 'Barangay '.$name;
        $parts[] = self::MUNICIPALITY;
        $parts[] = self::PROVINCE;

        return implode(', ', $parts);
    }

    /**
     * Parse the canonical address, returning null for unstructured legacy text.
     *
     * @return array{barangay: string, street: string}|null
     */
    public static function parse(string $address): ?array
    {
        $address = trim($address);

        foreach (TrinidadBarangay::cases() as $barangay) {
            $suffix = 'Barangay '.$barangay->value.', '.self::MUNICIPALITY.', '.self::PROVINCE;
            if ($address === $suffix) {
                return ['barangay' => $barangay->value, 'street' => ''];
            }

            $marker = ', '.$suffix;
            if (str_ends_with($address, $marker)) {
                $street = trim(substr($address, 0, -strlen($marker)));
                if ($street !== '') {
                    return ['barangay' => $barangay->value, 'street' => $street];
                }
            }
        }

        return null;
    }
}
