<?php

namespace App\Enums;

/**
 * Canonical vocabulary for the `inquiries.status` column.
 *
 * An inquiry is a buyer's structured contact with a seller about a listing. The
 * status is an administrator-facing workflow marker only: the buyer never sets
 * it, and it does not gate any mobile behaviour.
 */
enum InquiryStatus: string
{
    case Open = 'open';
    case Responded = 'responded';
    case Closed = 'closed';

    public function label(): string
    {
        return match ($this) {
            self::Open => 'Open',
            self::Responded => 'Responded',
            self::Closed => 'Closed',
        };
    }
}
