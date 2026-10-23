<?php

namespace App\Http\Requests\SellerVerification;

use App\Enums\SellerVerificationDocumentType;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

/**
 * One staged seller verification document.
 *
 * The body is a two-key allow-list: `type` names which document this is and
 * `document` is the file. Everything else is `prohibited`, so a client cannot
 * choose the owning account, name a storage path, or attach the file to
 * somebody else's application.
 *
 * The file rules are enforced on the server's own sniffing of the bytes, not on
 * the client's declared MIME type or filename:
 *
 *  - `mimes:jpg,jpeg,png,webp` restricts the container, and Laravel reads the
 *    actual content to decide it;
 *  - `max:5120` caps the upload at 5 MB;
 *  - `file` rejects a JSON string masquerading as an upload.
 *
 * A `422` is the right answer for all of them: the request is invalid input,
 * not a permission failure.
 */
class UploadSellerVerificationDocumentRequest extends FormRequest
{
    public function authorize(): bool
    {
        // Authentication and the mobile ability are the route's job; whether
        // this account may still apply (approved sellers cannot) is a state
        // rule enforced by the controller, where the record is available.
        return true;
    }

    /**
     * @return array<string, mixed>
     */
    public function rules(): array
    {
        return [
            'type' => [
                'required',
                Rule::enum(SellerVerificationDocumentType::class),
            ],
            'document' => [
                'required',
                'file',
                'mimes:jpg,jpeg,png,webp',
                'max:5120',
            ],

            // Server-owned. A client that sends one is told no, not ignored.
            'user_id' => ['prohibited'],
            'seller_verification_id' => ['prohibited'],
            'path' => ['prohibited'],
            'status' => ['prohibited'],
        ];
    }

    /**
     * @return array<string, string>
     */
    public function attributes(): array
    {
        return [
            'type' => 'document type',
            'document' => 'document',
        ];
    }

    /**
     * The validated document type.
     */
    public function documentType(): SellerVerificationDocumentType
    {
        return SellerVerificationDocumentType::from(
            $this->validated('type'),
        );
    }
}
