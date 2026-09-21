<?php

namespace Database\Seeders;

use App\Enums\SellerCapability;
use App\Enums\UserRole;
use App\Models\User;
use Illuminate\Database\Seeder;

class AdminSeeder extends Seeder
{
    /**
     * The placeholder password used when ADMIN_PASSWORD is left unconfigured.
     */
    private const PLACEHOLDER_PASSWORD = 'CHANGE_THIS_admin_password';

    /**
     * Create (or refresh) the administrator account.
     *
     * Credentials come from environment configuration. A placeholder password
     * is only used when the environment is left unconfigured, and a warning is
     * emitted so it cannot go unnoticed.
     */
    public function run(): void
    {
        $name = (string) (env('ADMIN_NAME') ?: 'Administrator');
        $email = (string) (env('ADMIN_EMAIL') ?: 'CHANGE_THIS_admin@example.com');
        $password = (string) (env('ADMIN_PASSWORD') ?: self::PLACEHOLDER_PASSWORD);

        $admin = User::query()->where('email', $email)->first();

        if ($this->hasNoCredentialsConfigured($email, $password)) {
            $this->command?->warn('Admin seed ran with placeholder credentials. Set ADMIN_NAME, ADMIN_EMAIL, and ADMIN_PASSWORD in backend/.env.');
        }

        if ($admin === null) {
            User::create([
                'name' => $name,
                'email' => $email,
                'password' => $password,
                'role' => UserRole::Admin,
                'seller_capability' => SellerCapability::Buyer,
                'email_verified_at' => now(),
            ]);

            return;
        }

        $admin->forceFill([
            'name' => $name,
            'role' => UserRole::Admin,
            'email_verified_at' => now(),
        ])->save();
    }

    private function hasNoCredentialsConfigured(string $email, string $password): bool
    {
        return str_contains($email, 'CHANGE_THIS') || $password === self::PLACEHOLDER_PASSWORD;
    }
}
