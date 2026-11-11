<?php

namespace Tests\Feature\Admin;

use App\Enums\SellerCapability;
use App\Enums\UserRole;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use PHPUnit\Framework\Attributes\DataProvider;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * An inquiry is between the buyer and the seller only (functional documentation
 * §8.2): the administrator has no inquiry screen and no inquiry endpoint, and
 * since the 2026-10-29 decision (MS-18) inquiries are delivered to the seller as
 * messages, so there is no seller inquiry inbox either.
 *
 * These routes used to exist under `/api/admin/inquiries*` and
 * `/api/seller/inquiries`. The tests pin the decision, so a route cannot
 * quietly come back.
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

    #[Test]
    public function a_seller_has_no_inquiry_inbox_endpoint(): void
    {
        $seller = User::factory()->create([
            'role' => UserRole::User,
            'seller_capability' => SellerCapability::Seller,
        ]);
        $token = $seller->createToken('mobile', ['mobile'])->plainTextToken;

        $this->withHeader('Authorization', "Bearer {$token}")
            ->getJson('/api/seller/inquiries')
            ->assertNotFound();
    }
}
