<?php

namespace App\Http\Requests\Report;

use App\Enums\UserReportReason;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

/**
 * Body for a mobile user report.
 *
 * The reporter is always the authenticated token owner, never a request field.
 * Moderation fields are server-owned and are refused rather than ignored.
 */
class StoreUserReportRequest extends FormRequest
{
    public function authorize(): bool
    {
        // `auth:sanctum` + `ability:mobile`; the service enforces the target
        // rules (self, administrator, deactivated, duplicate pending report).
        return true;
    }

    /**
     * @return array<string, mixed>
     */
    public function rules(): array
    {
        return [
            'reported_user_id' => ['required', 'integer', 'min:1'],
            'reason' => ['required', Rule::enum(UserReportReason::class)],
            'description' => ['required', 'string', 'min:10', 'max:2000', 'not_regex:/^\s*$/'],
            'evidence' => [
                'nullable',
                'file',
                'mimes:jpg,jpeg,png,webp',
                'mimetypes:image/jpeg,image/png,image/webp',
                'max:5120',
            ],

            'reporter_id' => ['prohibited'],
            'status' => ['prohibited'],
            'reviewed_by' => ['prohibited'],
            'reviewed_at' => ['prohibited'],
            'admin_note' => ['prohibited'],
            'evidence_path' => ['prohibited'],
            'id' => ['prohibited'],
            'created_at' => ['prohibited'],
            'updated_at' => ['prohibited'],
        ];
    }
}
