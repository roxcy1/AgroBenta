<?php

namespace App\Enums;

enum SellerVerificationStatus: string
{
    case Submitted = 'submitted';
    case PendingReview = 'pending_review';
    case Approved = 'approved';
    case Rejected = 'rejected';

    public function label(): string
    {
        return match ($this) {
            self::Submitted => 'Submitted',
            self::PendingReview => 'Pending Review',
            self::Approved => 'Approved',
            self::Rejected => 'Rejected',
        };
    }

    public function isOpen(): bool
    {
        return in_array($this, [self::Submitted, self::PendingReview], true);
    }
}
