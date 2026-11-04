<?php

namespace App\Enums;

enum GovernmentIdType: string
{
    case PhilippineNationalId = 'philippine_national_id';
    case DriversLicense = 'drivers_license';
    case PhilHealthId = 'philhealth_id';
    case VotersId = 'voters_id';
    case PostalId = 'postal_id';
    case Others = 'others';
}
