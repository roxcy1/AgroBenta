<?php

namespace Tests\Feature\Admin;

use App\Enums\SellerCapability;
use App\Enums\UserRole;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use PHPUnit\Framework\Attributes\DataProvider;
use Tests\TestCase;

/**
 * An inquiry is between the buyer and the seller only (functional documentation
 * §8.2): the administrator has no inquiry screen and no inquiry endpoint.
 *
 * These routes used to exist under `/api/admin/inquiries*`. The tests pin the
 * decision, so a route cannot quietly come back.
 */
class InquiryRoutesRemovedTest extends TestCase
{
    use RefreshDatabase;

    /**
     * @return array<string, array{string, string}>
     */
    public static function removedRoutes(): array
    {
        return [
            'list' => ['GET', '/api/admin/inquiries'],
            'show' => ['GET', '/api/admin/inquiries/1'],
            'update status' => ['PATCH', '/api/admin/inquiries/1/status'],
            'delete' => ['DELETE', '/api/admin/inquiries/1'],
        ];
    }

    #[DataProvider('removedRoutes')]
    public function test_an_administrator_has_no_inquiry_endpoint(string $method, string $uri): void
    {
        $admin = User::factory()->create([
            'role' => UserRole::Admin,
            'seller_capability' => SellerCapability::Buyer,
        ]);
        $token = $admin->createToken('admin_token', ['admin'])->plainTextToken;

        $this->withHeader('Authorization', "Bearer {$token}")
            ->json($method, $uri, $method === 'PATCH' ? ['status' => 'closed'] : [])
            ->assertNotFound();
    }
}
