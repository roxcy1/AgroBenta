<?php

namespace App\Enums;

use App\Services\ActivityLogger;

/**
 * Canonical vocabulary for the `activities.action` column.
 *
 * The action is the machine-readable verb of an audit entry. Every writer goes
 * through {@see ActivityLogger}, which takes one of these cases,
 * so the feed cannot accumulate near-duplicate strings such as
 * `listing_approved` and `approve_listing` for the same event, and a client can
 * filter on a value that is guaranteed to exist.
 */
enum ActivityAction: string
{
    case AdminLoggedIn = 'admin_logged_in';
    case UserLoggedIn = 'user_logged_in';

    case ListingCreated = 'listing_created';
    case ListingSubmitted = 'listing_submitted';
    case ListingUpdated = 'listing_updated';
    case ListingDeleted = 'listing_deleted';
    case ListingApproved = 'listing_approved';
    case ListingRejected = 'listing_rejected';
    case ListingDeactivated = 'listing_deactivated';
    case ListingPhotoRemoved = 'listing_photo_removed';

    case SellerVerificationSubmitted = 'seller_verification_submitted';
    case SellerVerificationApproved = 'seller_verification_approved';
    case SellerVerificationRejected = 'seller_verification_rejected';

    case TransactionCreated = 'transaction_created';
    case TransactionCancelled = 'transaction_cancelled';

    case SettingsUpdated = 'settings_updated';

    public function label(): string
    {
        return match ($this) {
            self::AdminLoggedIn => 'Administrator signed in',
            self::UserLoggedIn => 'User signed in',
            self::ListingCreated => 'Listing created',
            self::ListingSubmitted => 'Listing submitted',
            self::ListingUpdated => 'Listing updated',
            self::ListingDeleted => 'Listing deleted',
            self::ListingApproved => 'Listing approved',
            self::ListingRejected => 'Listing rejected',
            self::ListingDeactivated => 'Listing deactivated',
            self::ListingPhotoRemoved => 'Listing photo removed',
            self::SellerVerificationSubmitted => 'Seller verification submitted',
            self::SellerVerificationApproved => 'Seller verification approved',
            self::SellerVerificationRejected => 'Seller verification rejected',
            self::TransactionCreated => 'Transaction created',
            self::TransactionCancelled => 'Transaction cancelled',
            self::SettingsUpdated => 'Settings updated',
        };
    }
}
