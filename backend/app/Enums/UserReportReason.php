<?php

namespace App\Enums;

enum UserReportReason: string
{
    case ScamFraud = 'scam_fraud';
    case Harassment = 'harassment';
    case MisleadingInformation = 'misleading_information';
    case SpamSuspiciousActivity = 'spam_suspicious_activity';
    case InappropriateContent = 'inappropriate_content';
    case Other = 'other';

    public function label(): string
    {
        return match ($this) {
            self::ScamFraud => 'Scam/Fraud',
            self::Harassment => 'Harassment',
            self::MisleadingInformation => 'Misleading Information',
            self::SpamSuspiciousActivity => 'Spam/Suspicious Activity',
            self::InappropriateContent => 'Inappropriate Content',
            self::Other => 'Other',
        };
    }
}
