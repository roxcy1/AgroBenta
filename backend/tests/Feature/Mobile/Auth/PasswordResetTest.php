<?php

namespace Tests\Feature\Mobile\Auth;

use App\Models\User;
use Illuminate\Auth\Notifications\ResetPassword;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Notification;
use Tests\TestCase;

class PasswordResetTest extends TestCase
{
    use RefreshDatabase;

    public function test_forgot_password_returns_same_response_for_unknown_email(): void
    {
        Notification::fake();
        $r = $this->postJson('/api/auth/forgot-password', ['email' => 'does-not-exist@example.com']);
        $r->assertOk()->assertJson(['success' => true]);
    }

    public function test_reset_password_with_invalid_token_returns_422(): void
    {
        $u = User::factory()->create(['email' => 'u@example.com']);
        $r = $this->postJson('/api/auth/reset-password', ['token' => 'bad', 'email' => $u->email, 'password' => 'newpassword123', 'password_confirmation' => 'newpassword123']);
        $r->assertStatus(422)->assertJson(['success' => false]);
    }

    public function test_reset_password_with_valid_token_resets_password_and_revokes_tokens(): void
    {
        $u = User::factory()->create(['email' => 'u@example.com', 'password' => Hash::make('oldpassword')]);
        $u->createToken('mobile', ['mobile']);
        $this->assertCount(1, $u->tokens()->get());
        Notification::fake();
        $this->postJson('/api/auth/forgot-password', ['email' => $u->email])->assertOk();
        Notification::assertSentTo($u, ResetPassword::class, function (ResetPassword $n) use ($u) {
            $r = $this->postJson('/api/auth/reset-password', ['token' => $n->token, 'email' => $u->email, 'password' => 'newpassword123', 'password_confirmation' => 'newpassword123']);
            $r->assertOk()->assertJson(['success' => true]);
            $u->refresh();
            $this->assertTrue(Hash::check('newpassword123', $u->password));
            $this->assertCount(0, $u->tokens()->get());
            return true;
        });
    }

    public function test_forgot_password_is_throttled(): void
    {
        Notification::fake();
        for ($i = 0; $i < 6; $i++) {
            $e = 't' . $i . '@example.com';
            $r = $this->postJson('/api/auth/forgot-password', ['email' => $e]);
            if ($i < 5) { $r->assertOk(); }
        }
        $this->postJson('/api/auth/forgot-password', ['email' => 't5@example.com'])->assertStatus(429);
    }
}
