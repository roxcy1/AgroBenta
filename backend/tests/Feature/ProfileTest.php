<?php

namespace Tests\Feature;

use App\Enums\SellerCapability;
use App\Enums\UserRole;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

class ProfileTest extends TestCase
{
    use RefreshDatabase;

    private function mobileToken(User $user): string
    {
        return $user->createToken('mobile', ['mobile'])->plainTextToken;
    }

    #[Test]
    public function an_authenticated_user_can_retrieve_their_own_profile(): void
    {
        $user = User::factory()->create();
        $this->withHeader('Authorization', 'Bearer '.$this->mobileToken($user))
            ->getJson('/api/profile')
            ->assertOk()
            ->assertJsonPath('success', true)
            ->assertJsonPath('data.id', $user->id)
            ->assertJsonPath('data.email', $user->email);
    }

    #[Test]
    public function unauthenticated_access_to_profile_is_rejected(): void
    {
        $this->getJson('/api/profile')->assertUnauthorized();
        $this->putJson('/api/profile', ['name' => 'Test'])->assertUnauthorized();
        $this->putJson('/api/profile/password', [
            'current_password' => 'x',
            'password' => 'new-password-123',
            'password_confirmation' => 'new-password-123',
        ])->assertUnauthorized();
    }

    #[Test]
    public function sensitive_data_is_not_exposed_in_profile_response(): void
    {
        $user = User::factory()->create(['password' => 'secret-password']);
        $response = $this->withHeader('Authorization', 'Bearer '.$this->mobileToken($user))
            ->getJson('/api/profile')
            ->assertOk();
        $response->assertJsonMissing(['password']);
        $content = $response->getContent();
        $this->assertStringNotContainsString('secret-password', $content);
        $this->assertStringNotContainsString((string) $user->password, $content);
    }

    #[Test]
    public function an_authenticated_user_can_update_permitted_profile_fields(): void
    {
        $user = User::factory()->create(['name' => 'Juan Dela Cruz', 'phone' => null]);
        $this->withHeader('Authorization', 'Bearer '.$this->mobileToken($user))
            ->putJson('/api/profile', ['name' => 'Juan Updated', 'phone' => '09123456789', 'location' => 'Trinidad, Bohol'])
            ->assertOk()
            ->assertJsonPath('success', true)
            ->assertJsonPath('data.name', 'Juan Updated');
        $user->refresh();
        $this->assertSame('Juan Updated', $user->name);
    }

    #[Test]
    public function updating_profile_with_role_returns_422_and_does_not_change_role(): void
    {
        $user = User::factory()->create(['role' => UserRole::User]);
        $originalRole = $user->role;
        $this->withHeader('Authorization', 'Bearer '.$this->mobileToken($user))
            ->putJson('/api/profile', ['role' => UserRole::Admin->value])
            ->assertUnprocessable();
        $user->refresh();
        $this->assertSame($originalRole->value, $user->role->value);
    }

    #[Test]
    public function updating_profile_with_seller_capability_returns_422_and_does_not_change_seller_capability(): void
    {
        $user = User::factory()->create(['seller_capability' => SellerCapability::Buyer]);
        $original = $user->seller_capability;
        $this->withHeader('Authorization', 'Bearer '.$this->mobileToken($user))
            ->putJson('/api/profile', ['seller_capability' => SellerCapability::Seller->value])
            ->assertUnprocessable();
        $user->refresh();
        $this->assertSame($original->value, $user->seller_capability->value);
    }

    #[Test]
    public function updating_profile_with_id_returns_422_and_does_not_change_id(): void
    {
        $user = User::factory()->create();
        $originalId = $user->id;
        $this->withHeader('Authorization', 'Bearer '.$this->mobileToken($user))
            ->putJson('/api/profile', ['id' => 99999])
            ->assertUnprocessable();
        $user->refresh();
        $this->assertSame($originalId, $user->id);
    }

    #[Test]
    public function updating_profile_with_password_returns_422_and_does_not_change_password_hash(): void
    {
        $user = User::factory()->create(['password' => 'old-password']);
        $originalHash = $user->getAuthPassword();
        $this->withHeader('Authorization', 'Bearer '.$this->mobileToken($user))
            ->putJson('/api/profile', ['password' => 'new-password-123'])
            ->assertUnprocessable();
        $user->refresh();
        $this->assertSame($originalHash, $user->getAuthPassword());
        $this->assertTrue(Hash::check('old-password', $user->getAuthPassword()));
    }

    #[Test]
    public function changing_email_without_current_password_returns_422(): void
    {
        $user = User::factory()->create(['email' => 'old@example.test', 'password' => 'password123']);
        $this->withHeader('Authorization', 'Bearer '.$this->mobileToken($user))
            ->putJson('/api/profile', ['email' => 'new@example.test'])
            ->assertUnprocessable();
        $user->refresh();
        $this->assertSame('old@example.test', $user->email);
    }

    #[Test]
    public function changing_email_with_incorrect_current_password_returns_422(): void
    {
        $user = User::factory()->create(['email' => 'old@example.test', 'password' => 'password123']);
        $this->withHeader('Authorization', 'Bearer '.$this->mobileToken($user))
            ->putJson('/api/profile', ['email' => 'new@example.test', 'current_password' => 'wrong-password'])
            ->assertUnprocessable();
        $user->refresh();
        $this->assertSame('old@example.test', $user->email);
    }

    #[Test]
    public function changing_email_with_correct_current_password_succeeds(): void
    {
        $user = User::factory()->create(['email' => 'old@example.test', 'password' => 'password123']);
        $this->withHeader('Authorization', 'Bearer '.$this->mobileToken($user))
            ->putJson('/api/profile', ['email' => 'new@example.test', 'current_password' => 'password123'])
            ->assertOk()
            ->assertJsonPath('success', true)
            ->assertJsonPath('data.email', 'new@example.test');
        $user->refresh();
        $this->assertSame('new@example.test', $user->email);
    }

    #[Test]
    public function changing_email_to_another_users_email_returns_422(): void
    {
        User::factory()->create(['email' => 'taken@example.test']);
        $user = User::factory()->create(['email' => 'old@example.test', 'password' => 'password123']);
        $this->withHeader('Authorization', 'Bearer '.$this->mobileToken($user))
            ->putJson('/api/profile', ['email' => 'taken@example.test', 'current_password' => 'password123'])
            ->assertUnprocessable();
        $user->refresh();
        $this->assertSame('old@example.test', $user->email);
    }

    #[Test]
    public function failed_email_change_leaves_stored_email_unchanged(): void
    {
        $user = User::factory()->create(['email' => 'old@example.test', 'password' => 'password123']);
        $this->withHeader('Authorization', 'Bearer '.$this->mobileToken($user))
            ->putJson('/api/profile', ['email' => 'new@example.test', 'current_password' => 'wrong'])
            ->assertUnprocessable();
        $user->refresh();
        $this->assertSame('old@example.test', $user->email);
    }

    #[Test]
    public function updating_email_to_its_existing_value_does_not_require_current_password(): void
    {
        $user = User::factory()->create(['email' => 'same@example.test', 'password' => 'password123']);
        $this->withHeader('Authorization', 'Bearer '.$this->mobileToken($user))
            ->putJson('/api/profile', ['email' => 'same@example.test'])
            ->assertOk()
            ->assertJsonPath('data.email', 'same@example.test');
        $user->refresh();
        $this->assertSame('same@example.test', $user->email);
    }

    #[Test]
    public function updating_other_permitted_profile_fields_without_changing_email_still_succeeds(): void
    {
        $user = User::factory()->create(['email' => 'user@example.test', 'name' => 'Old Name', 'password' => 'password123']);
        $this->withHeader('Authorization', 'Bearer '.$this->mobileToken($user))
            ->putJson('/api/profile', ['name' => 'New Name', 'phone' => '09111111111'])
            ->assertOk()
            ->assertJsonPath('data.name', 'New Name')
            ->assertJsonPath('data.email', 'user@example.test');
        $user->refresh();
        $this->assertSame('New Name', $user->name);
    }

    #[Test]
    public function successful_password_change_updates_hash_and_response_format(): void
    {
        $user = User::factory()->create(['password' => 'old-password']);
        $token = $user->createToken('mobile', ['mobile'])->plainTextToken;
        $this->withHeader('Authorization', 'Bearer '.$token)
            ->putJson('/api/profile/password', ['current_password' => 'old-password', 'password' => 'new-password-123', 'password_confirmation' => 'new-password-123'])
            ->assertOk()
            ->assertJsonPath('success', true)
            ->assertJsonPath('message', 'Password changed.');
        $user->refresh();
        $this->assertTrue(Hash::check('new-password-123', $user->getAuthPassword()));
        $this->assertFalse(Hash::check('old-password', $user->getAuthPassword()));
    }

    #[Test]
    public function current_token_remains_valid_after_password_change(): void
    {
        $user = User::factory()->create(['password' => 'old-password']);
        $token = $user->createToken('mobile', ['mobile'])->plainTextToken;
        $this->withHeader('Authorization', 'Bearer '.$token)
            ->putJson('/api/profile/password', ['current_password' => 'old-password', 'password' => 'new-password-123', 'password_confirmation' => 'new-password-123'])
            ->assertOk();
        $this->withHeader('Authorization', 'Bearer '.$token)
            ->getJson('/api/profile')
            ->assertOk()
            ->assertJsonPath('success', true);
    }

    #[Test]
    public function other_tokens_belonging_to_same_user_are_revoked(): void
    {
        $user = User::factory()->create(['password' => 'old-password']);
        $currentToken = $user->createToken('mobile', ['mobile'])->plainTextToken;
        $otherToken = $user->createToken('mobile', ['mobile'])->plainTextToken;
        $this->assertCount(2, $user->tokens()->get());
        $this->withHeader('Authorization', 'Bearer '.$currentToken)
            ->putJson('/api/profile/password', ['current_password' => 'old-password', 'password' => 'new-password-123', 'password_confirmation' => 'new-password-123'])
            ->assertOk();
        $this->assertCount(1, $user->tokens()->get());
        $this->withHeader('Authorization', 'Bearer '.$otherToken)
            ->getJson('/api/profile')
            ->assertUnauthorized();
        $this->withHeader('Authorization', 'Bearer '.$currentToken)
            ->getJson('/api/profile')
            ->assertOk();
    }

    #[Test]
    public function tokens_belonging_to_another_user_remain_valid(): void
    {
        $user = User::factory()->create(['password' => 'old-password']);
        $otherUser = User::factory()->create(['password' => 'other-password']);
        $currentToken = $user->createToken('mobile', ['mobile'])->plainTextToken;
        $otherUserToken = $otherUser->createToken('mobile', ['mobile'])->plainTextToken;
        $this->withHeader('Authorization', 'Bearer '.$currentToken)
            ->putJson('/api/profile/password', ['current_password' => 'old-password', 'password' => 'new-password-123', 'password_confirmation' => 'new-password-123'])
            ->assertOk();
        $this->withHeader('Authorization', 'Bearer '.$otherUserToken)
            ->getJson('/api/profile')
            ->assertOk()
            ->assertJsonPath('success', true)
            ->assertJsonPath('data.id', $otherUser->id);
    }

    #[Test]
    public function incorrect_current_password_does_not_change_password_or_revoke_tokens(): void
    {
        $user = User::factory()->create(['password' => 'old-password']);
        $currentToken = $user->createToken('mobile', ['mobile'])->plainTextToken;
        $originalHash = $user->getAuthPassword();
        $this->withHeader('Authorization', 'Bearer '.$currentToken)
            ->putJson('/api/profile/password', ['current_password' => 'wrong-password', 'password' => 'new-password-123', 'password_confirmation' => 'new-password-123'])
            ->assertUnprocessable();
        $user->refresh();
        $this->assertSame($originalHash, $user->getAuthPassword());
        $this->assertTrue(Hash::check('old-password', $user->getAuthPassword()));
        $this->assertCount(1, $user->tokens()->get());
    }

    #[Test]
    public function invalid_new_password_does_not_change_password_or_revoke_tokens(): void
    {
        $user = User::factory()->create(['password' => 'old-password']);
        $currentToken = $user->createToken('mobile', ['mobile'])->plainTextToken;
        $originalHash = $user->getAuthPassword();
        $this->withHeader('Authorization', 'Bearer '.$currentToken)
            ->putJson('/api/profile/password', ['current_password' => 'old-password', 'password' => 'short', 'password_confirmation' => 'short'])
            ->assertUnprocessable();
        $user->refresh();
        $this->assertSame($originalHash, $user->getAuthPassword());
        $this->assertTrue(Hash::check('old-password', $user->getAuthPassword()));
        $this->assertCount(1, $user->tokens()->get());
    }

    #[Test]
    public function user_cannot_retrieve_another_users_profile(): void
    {
        $userA = User::factory()->create(['email' => 'a@example.test']);
        User::factory()->create(['email' => 'b@example.test']);
        $this->withHeader('Authorization', 'Bearer '.$this->mobileToken($userA))
            ->getJson('/api/profile')
            ->assertOk()
            ->assertJsonPath('data.email', 'a@example.test')
            ->assertJsonPath('data.id', $userA->id);
    }

    #[Test]
    public function user_cannot_update_another_users_profile(): void
    {
        $userA = User::factory()->create(['name' => 'User A', 'password' => 'password123']);
        $userB = User::factory()->create(['name' => 'User B', 'password' => 'password123']);
        $this->withHeader('Authorization', 'Bearer '.$this->mobileToken($userA))
            ->putJson('/api/profile', ['name' => 'Hacked'])
            ->assertOk();
        $userA->refresh();
        $userB->refresh();
        $this->assertSame('Hacked', $userA->name);
        $this->assertSame('User B', $userB->name);
    }

    #[Test]
    public function user_cannot_change_another_users_password(): void
    {
        $userA = User::factory()->create(['password' => 'password123']);
        $userB = User::factory()->create(['password' => 'otherpassword']);
        $this->withHeader('Authorization', 'Bearer '.$this->mobileToken($userA))
            ->putJson('/api/profile/password', ['current_password' => 'password123', 'password' => 'newpassword456', 'password_confirmation' => 'newpassword456'])
            ->assertOk();
        $userA->refresh();
        $userB->refresh();
        $this->assertTrue(Hash::check('newpassword456', $userA->getAuthPassword()));
        $this->assertTrue(Hash::check('otherpassword', $userB->getAuthPassword()));
    }
}
