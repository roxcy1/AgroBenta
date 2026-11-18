<?php

namespace App\Enums;

enum UserReportStatus: string
{
    case Pending = 'pending';
    case Dismissed = 'dismissed';
    case Actioned = 'actioned';

    public function label(): string
    {
        return match ($this) {
            self::Pending => 'Pending',
            self::Dismissed => 'Dismissed',
            self::Actioned => 'Actioned',
        };
    }

    public function isPending(): bool
    {
        return $this === self::Pending;
    }
}
