<?php

namespace App\Enums;

enum SellerCapability: string
{
    case Buyer = 'buyer';
    case Seller = 'seller';

    public function label(): string
    {
        return match ($this) {
            self::Buyer => 'Buyer / Not a Seller',
            self::Seller => 'Approved Seller',
        };
    }
}
