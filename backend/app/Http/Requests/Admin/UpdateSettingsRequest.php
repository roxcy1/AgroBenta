<?php

namespace App\Http\Requests\Admin;

use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Validator;

/**
 * Validation for a bulk settings update.
 *
 * The body is a flat `key => value` map, so the rules are looked up per key
 * rather than written as a static rule array. Every recognised key is described
 * by the registry in `config/settings.php`; unknown keys are left to the
 * service, which reports them in `rejected` (the documented contract), and are
 * never persisted.
 *
 * A body with at least one invalid value is a 422 for the whole request: the
 * controller never reaches the service, so a rejected update cannot partially
 * save. Bounds are what stop a bad setting from switching a business rule off —
 * `listing.max_photos` cannot be zero or negative, `listing.max_price` cannot be
 * negative, and `system.name` cannot be emptied.
 */
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
            $definitions = config('settings.keys');

            foreach ($this->input() as $key => $value) {
                if (! is_string($value)) {
                    $validator->errors()->add($key, 'The value must be a string.');

                    continue;
                }

                $definition = $definitions[$key] ?? null;

                if ($definition === null) {
                    continue;
                }

                $this->validateValue($validator, $key, $value, $definition);
            }
        });
    }

    /**
     * @param  array<string, mixed>  $definition
     */
    private function validateValue(Validator $validator, string $key, string $value, array $definition): void
    {
        if (($definition['required'] ?? false) && trim($value) === '') {
            $validator->errors()->add($key, 'The value is required.');

            return;
        }

        // An optional setting may be cleared; nothing further to check.
        if ($value === '') {
            return;
        }

        match ($definition['type'] ?? 'string') {
            'email' => $this->validateEmail($validator, $key, $value, $definition),
            'integer' => $this->validateNumber($validator, $key, $value, $definition, true),
            'decimal' => $this->validateNumber($validator, $key, $value, $definition, false),
            default => $this->validateMaxLength($validator, $key, $value, $definition),
        };
    }

    /**
     * @param  array<string, mixed>  $definition
     */
    private function validateEmail(Validator $validator, string $key, string $value, array $definition): void
    {
        if (! filter_var($value, FILTER_VALIDATE_EMAIL)) {
            $validator->errors()->add($key, 'The :attribute must be a valid email address.');

            return;
        }

        $this->validateMaxLength($validator, $key, $value, $definition);
    }

    /**
     * Validate an integer or decimal setting against the registry's bounds.
     *
     * @param  array<string, mixed>  $definition
     */
    private function validateNumber(
        Validator $validator,
        string $key,
        string $value,
        array $definition,
        bool $integer,
    ): void {
        if (! is_numeric($value)) {
            $validator->errors()->add($key, 'The :attribute must be a number.');

            return;
        }

        if ($integer && ! preg_match('/^-?\d+$/', $value)) {
            $validator->errors()->add($key, 'The :attribute must be a whole number.');

            return;
        }

        $number = (float) $value;

        if (isset($definition['min']) && $number < (float) $definition['min']) {
            $validator->errors()->add(
                $key,
                'The :attribute must be at least '.$definition['min'].'.',
            );
        }

        if (isset($definition['max']) && $number > (float) $definition['max']) {
            $validator->errors()->add(
                $key,
                'The :attribute must not be greater than '.$definition['max'].'.',
            );
        }
    }

    /**
     * @param  array<string, mixed>  $definition
     */
    private function validateMaxLength(Validator $validator, string $key, string $value, array $definition): void
    {
        $max = $definition['max_length'] ?? null;

        if ($max !== null && mb_strlen($value) > (int) $max) {
            $validator->errors()->add($key, "The :attribute must not exceed {$max} characters.");
        }
    }
}
