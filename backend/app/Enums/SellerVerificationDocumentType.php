<?php

namespace App\Enums;

/**
 * The documents a seller application can carry (functional documentation §3.3).
 *
 * `id_document` is a government-issued ID, `proof_of_address` is for example a
 * utility bill or barangay certificate, and `farm_photo` is an optional photo of
 * the seller's livestock or farm area. `selfie` is the applicant holding the
 * same ID; it is not in the manuscript and its future is open (MS-05). The ID
 * and the selfie are separate uploads on purpose: reusing the ID image as the
 * selfie would defeat the check the administrator is being asked to make.
 *
 * The string values are the API's `type` parameter and the filenames' stem; no
 * other spelling is accepted.
 */
enum SellerVerificationDocumentType: string
{
    case IdDocument = 'id_document';
    case IdDocumentFront = 'id_document_front';
    case IdDocumentBack = 'id_document_back';
    case Selfie = 'selfie';
    case ProofOfAddress = 'proof_of_address';
    case FarmPhoto = 'farm_photo';

    /**
     * The column on `seller_verifications` the promoted path is written to.
     * For a type that {@see allowsMultiple()}, the column holds a JSON list.
     */
    public function column(): string
    {
        return match ($this) {
            self::IdDocument => 'id_document_path',
            self::IdDocumentFront => 'id_document_front_path',
            self::IdDocumentBack => 'id_document_back_path',
            self::Selfie => 'selfie_path',
            self::ProofOfAddress => 'proof_of_address_path',
            self::FarmPhoto => 'farm_photo_paths',
        };
    }

    /**
     * Whether an application can hold several files of this type. Such a type
     * adds a file on each upload instead of replacing the previous one.
     */
    public function allowsMultiple(): bool
    {
        return $this === self::FarmPhoto;
    }

    /**
     * Whether an application must include this document before it is submitted.
     */
    public function isRequired(): bool
    {
        return in_array($this, [
            self::IdDocumentFront,
            self::Selfie,
            self::ProofOfAddress,
        ], true);
    }

    /**
     * The message for a required document missing at submission.
     */
    public function missingMessage(): string
    {
        return match ($this) {
            self::IdDocument => 'Upload a clear photo of your government-issued ID.',
            self::IdDocumentFront => 'Upload the front of your government-issued ID.',
            self::IdDocumentBack => 'Upload the back of your government-issued ID.',
            self::Selfie => 'Upload a selfie holding the same ID.',
            self::ProofOfAddress => 'Upload your proof of address.',
            self::FarmPhoto => 'Upload a farm photo.',
        };
    }
}
