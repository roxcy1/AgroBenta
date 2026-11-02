<?php

namespace App\Enums;

/**
 * The buyer's chosen collection-date preference for an inquiry.
 *
 * `specific_date` means the buyer named a concrete date (stored in
 * `preferred_schedule`, which must not be in the past). `next_few_days` and
 * `this_week` are relative preferences and do not require a date.
 */
enum InquiryCollectionDateOption: string
{
    case SpecificDate = 'specific_date';
    case NextFewDays = 'next_few_days';
    case ThisWeek = 'this_week';

    public function label(): string
    {
        return match ($this) {
            self::SpecificDate => 'Specific date',
            self::NextFewDays => 'Within the next few days',
            self::ThisWeek => 'Within this week',
        };
    }
}
