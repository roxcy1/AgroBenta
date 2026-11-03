<?php

namespace Tests\Feature\LivestockType;

use App\Enums\SellerCapability;
use App\Enums\UserRole;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

class LivestockTypeTest extends TestCase
{
    use RefreshDatabase;

    private function token(User $user, string $ability): string
    {
        return $user->createToken($ability, [$ability])->plainTextToken;
    }

    #[Test]
    public function a_guest_cannot_read_the_catalog(): void
    {
        $this->getJson('/api/livestock-types')->assertUnauthorized();
    }

    #[Test]
    public function a_mobile_token_receives_the_exact_catalog(): void
    {
        $user = User::factory()->create([
            'role' => UserRole::User,
            'seller_capability' => SellerCapability::Buyer,
        ]);

        $this->withHeader('Authorization', 'Bearer '.$this->token($user, 'mobile'))
            ->getJson('/api/livestock-types')
            ->assertOk()
            ->assertExactJson([
                'data' => [
                    ['value' => 'cattle', 'label' => 'Cattle'],
                    ['value' => 'carabao', 'label' => 'Carabao'],
                    ['value' => 'goat', 'label' => 'Goat'],
                    ['value' => 'swine', 'label' => 'Swine'],
                ],
            ]);
    }

    #[Test]
    public function an_admin_token_receives_the_exact_catalog(): void
    {
        $admin = User::factory()->create([
            'role' => UserRole::Admin,
            'seller_capability' => SellerCapability::Buyer,
        ]);

        $this->withHeader('Authorization', 'Bearer '.$this->token($admin, 'admin'))
            ->getJson('/api/livestock-types')
            ->assertOk()
            ->assertExactJson([
                'data' => [
                    ['value' => 'cattle', 'label' => 'Cattle'],
                    ['value' => 'carabao', 'label' => 'Carabao'],
                    ['value' => 'goat', 'label' => 'Goat'],
                    ['value' => 'swine', 'label' => 'Swine'],
                ],
            ]);
    }
}
