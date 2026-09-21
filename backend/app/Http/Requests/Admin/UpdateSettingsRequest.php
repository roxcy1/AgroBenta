<?php

namespace App\Http\Requests\Admin;

use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Validator;

class UpdateSettingsRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    public function rules(): array
    {
        return [];
    }

    /**
     * Return all input since rules are handled via withValidator.
     */
    public function validated($key = null, $default = null): mixed
    {
        $data = $this->input();

        if ($key === null) {
            return $data;
        }

        return data_get($data, $key, $default);
    }

    protected function withValidator(Validator $validator): void
    {
        $validator->after(function (Validator $validator): void {
            foreach ($this->input() as $key => $value) {
                if (! is_string($value)) {
                    $validator->errors()->add($key, 'The value must be a string.');

                    continue;
                }

                match ($key) {
                    'system.name' => $this->validateMaxLength($validator, $key, $value, 255),
                    'system.description' => $this->validateMaxLength($validator, $key, $value, 1000),
                    'admin_contact.name' => $this->validateMaxLength($validator, $key, $value, 255),
                    'admin_contact.email' => $this->validateEmail($validator, $key, $value),
                    'admin_contact.phone' => $this->validateMaxLength($validator, $key, $value, 50),
                    default => null,
                };
            }
        });
    }

    private function validateMaxLength(Validator $validator, string $key, string $value, int $max): void
    {
        if (mb_strlen($value) > $max) {
            $validator->errors()->add($key, "The :attribute must not exceed {$max} characters.");
        }
    }

    private function validateEmail(Validator $validator, string $key, string $value): void
    {
        if (! filter_var($value, FILTER_VALIDATE_EMAIL)) {
            $validator->errors()->add($key, 'The :attribute must be a valid email address.');
        }
    }
}
