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
                    [
                        'value' => 'cattle',
                        'label' => 'Cattle',
                        'breeds' => [
                            'brahman',
                            'brahman_cross',
                            'holstein_friesian',
                            'philippine_native_cattle',
                        ],
                    ],
                    [
                        'value' => 'carabao',
                        'label' => 'Carabao',
                        'breeds' => [
                            'murrah',
                            'native_murrah_cross',
                            'philippine_native_carabao',
                        ],
                    ],
                    [
                        'value' => 'goat',
                        'label' => 'Goat',
                        'breeds' => [
                            'anglo_nubian',
                            'boer',
                            'saanen',
                            'ubay_boholano_native_goat',
                        ],
                    ],
                    [
                        'value' => 'swine',
                        'label' => 'Swine',
                        'breeds' => [
                            'duroc',
                            'duroc_landrace_cross',
                            'landrace',
                            'large_white_yorkshire',
                            'native_pig',
                        ],
                    ],
                    [
                        'value' => 'chicken',
                        'label' => 'Chicken',
                        'breeds' => [
                            'boholano_native_chicken',
                            'broiler',
                            'improved_native_chicken',
                            'layer',
                        ],
                    ],
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
                    [
                        'value' => 'cattle',
                        'label' => 'Cattle',
                        'breeds' => [
                            'brahman',
                            'brahman_cross',
                            'holstein_friesian',
                            'philippine_native_cattle',
                        ],
                    ],
                    [
                        'value' => 'carabao',
                        'label' => 'Carabao',
                        'breeds' => [
                            'murrah',
                            'native_murrah_cross',
                            'philippine_native_carabao',
                        ],
                    ],
                    [
                        'value' => 'goat',
                        'label' => 'Goat',
                        'breeds' => [
                            'anglo_nubian',
                            'boer',
                            'saanen',
                            'ubay_boholano_native_goat',
                        ],
                    ],
                    [
                        'value' => 'swine',
                        'label' => 'Swine',
                        'breeds' => [
                            'duroc',
                            'duroc_landrace_cross',
                            'landrace',
                            'large_white_yorkshire',
                            'native_pig',
                        ],
                    ],
                    [
                        'value' => 'chicken',
                        'label' => 'Chicken',
                        'breeds' => [
                            'boholano_native_chicken',
                            'broiler',
                            'improved_native_chicken',
                            'layer',
                        ],
                    ],
                ],
            ]);
    }
}
