<?php

namespace App\Enums;

/**
 * The two documents a seller application must carry.
 *
 * `id_document` is a government-issued ID and `selfie` is the applicant holding
 * that same ID. They are separate uploads on purpose: reusing the ID image as
 * the selfie would defeat the check the administrator is being asked to make.
 *
 * The string values are the API's `type` parameter and the filenames' stem; no
 * other spelling is accepted.
 */
enum SellerVerificationDocumentType: string
{
    case IdDocument = 'id_document';
    case Selfie = 'selfie';

    /**
     * The column on `seller_verifications` the promoted path is written to.
     */
    public function column(): string
    {
        return match ($this) {
            self::IdDocument => 'id_document_path',
            self::Selfie => 'selfie_path',
        };
    }
}
