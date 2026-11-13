<?php

namespace Tests\Feature\Location;

use App\Enums\SellerCapability;
use App\Enums\TrinidadBarangay;
use App\Enums\UserRole;
use App\Models\User;
use App\Support\TrinidadLocationAddress;
use Illuminate\Foundation\Testing\RefreshDatabase;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

class TrinidadLocationTest extends TestCase
{
    use RefreshDatabase;

    private function token(User $user, string $ability): string
    {
        return $user->createToken($ability, [$ability])->plainTextToken;
    }

    #[Test]
    public function a_guest_cannot_read_the_trinidad_catalog(): void
    {
        $this->getJson('/api/locations/trinidad/barangays')->assertUnauthorized();
    }

    #[Test]
    public function a_mobile_token_receives_the_name_only_catalog(): void
    {
        $user = User::factory()->create([
            'role' => UserRole::User,
            'seller_capability' => SellerCapability::Buyer,
        ]);

        $this->withHeader('Authorization', 'Bearer '.$this->token($user, 'mobile'))
            ->getJson('/api/locations/trinidad/barangays')
            ->assertOk()
            ->assertExactJson([
                'success' => true,
                'message' => 'Trinidad location catalog retrieved.',
                'data' => [
                    'region' => 'Central Visayas (Region VII)',
                    'province' => 'Bohol',
                    'municipality' => 'Trinidad',
                    'barangays' => [
                        'Banlasan',
                        'Bongbong',
                        'Catoogan',
                        'Guinobatan',
                        'Hinlayagan Ilaud',
                        'Hinlayagan Ilaya',
                        'Kauswagan',
                        'Kinan-oan',
                        'La Union',
                        'La Victoria',
                        'Mabuhay Cabigohan',
                        'Mahagbu',
                        'Manuel M. Roxas',
                        'Poblacion',
                        'San Isidro',
                        'San Vicente',
                        'Santo Tomas',
                        'Soom',
                        'Tagum Norte',
                        'Tagum Sur',
                    ],
                ],
            ]);
    }

    #[Test]
    public function an_admin_token_cannot_read_the_mobile_location_catalog(): void
    {
        $admin = User::factory()->create([
            'role' => UserRole::Admin,
            'seller_capability' => SellerCapability::Buyer,
        ]);

        $this->withHeader('Authorization', 'Bearer '.$this->token($admin, 'admin'))
            ->getJson('/api/locations/trinidad/barangays')
            ->assertForbidden();
    }

    #[Test]
    public function formatted_addresses_round_trip_without_codes(): void
    {
        $formatted = TrinidadLocationAddress::format(
            TrinidadBarangay::Poblacion->value,
            'Purok 3',
        );

        $this->assertSame(
            'Purok 3, Barangay Poblacion, Trinidad, Bohol',
            $formatted,
        );
        $this->assertSame(
            ['barangay' => 'Poblacion', 'street' => 'Purok 3'],
            TrinidadLocationAddress::parse($formatted),
        );
        $this->assertSame(
            ['barangay' => 'Poblacion', 'street' => ''],
            TrinidadLocationAddress::parse('Barangay Poblacion, Trinidad, Bohol'),
        );
        $this->assertNull(TrinidadLocationAddress::parse('Trinidad, Bohol'));
    }
}
