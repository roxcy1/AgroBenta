<?php

namespace Tests\Feature\Mobile\Auth;

use App\Enums\UserRole;
use App\Models\User;
use App\Services\MobileAuthService;
use Illuminate\Auth\Notifications\ResetPassword;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Notification;
use Illuminate\Support\Facades\Password;
use Illuminate\Testing\TestResponse;
use RuntimeException;
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

    public function test_the_emailed_code_is_six_digits_and_the_email_renders(): void
    {
        $user = User::factory()->create(['email' => 'u@example.com']);

        $code = $this->requestCode($user);

        $this->assertMatchesRegularExpression('/^\d{6}$/', $code);
        $mail = (new ResetPassword($code))->toMail($user);
        $this->assertStringContainsString($code, (string) $mail->render());
    }

    public function test_the_email_is_really_sent_through_the_mailer(): void
    {
        $user = User::factory()->create(['email' => 'u@example.com']);

        $this->postJson('/api/auth/forgot-password', ['email' => $user->email])->assertOk();

        $messages = app('mailer')->getSymfonyTransport()->messages();
        $this->assertCount(1, $messages);
        $this->assertMatchesRegularExpression('/\b\d{6}\b/', $messages->first()->toString());
    }

    public function test_replies_match_for_known_and_unknown_emails(): void
    {
        Notification::fake();
        User::factory()->create(['email' => 'u@example.com']);

        $known = $this->postJson('/api/auth/forgot-password', ['email' => 'u@example.com']);
        $unknown = $this->postJson('/api/auth/forgot-password', ['email' => 'none@example.com']);

        $this->assertSame($known->json(), $unknown->json());
    }

    public function test_a_mail_failure_does_not_change_the_reply(): void
    {
        Password::shouldReceive('sendResetLink')->once()->andThrow(new RuntimeException('SMTP down'));

        $this->postJson('/api/auth/forgot-password', ['email' => 'u@example.com'])
            ->assertOk()
            ->assertJson(['success' => true]);
    }

    public function test_an_administrator_gets_the_same_reply_but_no_code(): void
    {
        Notification::fake();
        $admin = User::factory()->create(['email' => 'admin@example.com', 'role' => UserRole::Admin]);

        $this->postJson('/api/auth/forgot-password', ['email' => $admin->email])
            ->assertOk()
            ->assertJson(['success' => true]);

        Notification::assertNothingSent();
    }

    public function test_a_code_can_only_be_used_once(): void
    {
        $user = User::factory()->create(['email' => 'u@example.com']);
        $code = $this->requestCode($user);

        $this->reset($user, $code)->assertOk();
        $this->reset($user, $code, 'anotherpassword1')->assertStatus(422);

        $this->assertTrue(Hash::check('newpassword123', $user->fresh()->password));
    }

    public function test_an_expired_code_is_rejected(): void
    {
        $user = User::factory()->create(['email' => 'u@example.com', 'password' => Hash::make('oldpassword')]);
        $code = $this->requestCode($user);

        $this->travel(61)->minutes();

        $this->reset($user, $code)->assertStatus(422)->assertJson(['success' => false]);
        $this->assertTrue(Hash::check('oldpassword', $user->fresh()->password));
    }

    public function test_an_unknown_email_gets_the_same_reply_as_a_wrong_code(): void
    {
        $user = User::factory()->create(['email' => 'u@example.com']);

        $wrongCode = $this->reset($user, '000000');
        $unknownEmail = $this->postJson('/api/auth/reset-password', [
            'token' => '000000',
            'email' => 'none@example.com',
            'password' => 'newpassword123',
            'password_confirmation' => 'newpassword123',
        ]);

        $unknownEmail->assertStatus(422);
        $this->assertSame($wrongCode->json(), $unknownEmail->json());
    }

    public function test_too_many_wrong_codes_lock_out_even_the_right_code(): void
    {
        $user = User::factory()->create(['email' => 'u@example.com', 'password' => Hash::make('oldpassword')]);
        $code = $this->requestCode($user);
        $wrong = $code === '000000' ? '000001' : '000000';

        for ($i = 0; $i < MobileAuthService::MAX_RESET_CODE_ATTEMPTS; $i++) {
            $this->withServerVariables(['REMOTE_ADDR' => "10.0.0.{$i}"]);
            $this->reset($user, $wrong)->assertStatus(422);
        }

        $this->withServerVariables(['REMOTE_ADDR' => '10.0.1.1']);
        $this->reset($user, $code)->assertStatus(422);

        $this->assertTrue(Hash::check('oldpassword', $user->fresh()->password));
    }

    public function test_reset_password_is_throttled_per_client(): void
    {
        $user = User::factory()->create(['email' => 'u@example.com']);

        for ($i = 0; $i < 5; $i++) {
            $this->reset($user, '000000')->assertStatus(422);
        }

        $this->reset($user, '000000')->assertStatus(429);
    }

    public function test_old_tokens_stop_working_and_the_new_password_signs_in(): void
    {
        $user = User::factory()->create(['email' => 'u@example.com', 'password' => Hash::make('oldpassword')]);
        $oldToken = $user->createToken('mobile', ['mobile'])->plainTextToken;
        $code = $this->requestCode($user);

        $this->reset($user, $code)->assertOk();

        $this->app['auth']->forgetGuards();
        $this->withToken($oldToken)->getJson('/api/auth/me')->assertUnauthorized();

        $this->app['auth']->forgetGuards();
        $this->withoutToken()->postJson('/api/auth/login', ['email' => $user->email, 'password' => 'oldpassword'])
            ->assertUnauthorized();
        $this->postJson('/api/auth/login', ['email' => $user->email, 'password' => 'newpassword123'])
            ->assertOk();
    }

    private function requestCode(User $user): string
    {
        Notification::fake();
        $this->postJson('/api/auth/forgot-password', ['email' => $user->email])->assertOk();

        $code = null;
        Notification::assertSentTo($user, ResetPassword::class, function (ResetPassword $notification) use (&$code) {
            $code = $notification->token;

            return true;
        });

        return $code;
    }

    private function reset(User $user, string $code, string $password = 'newpassword123'): TestResponse
    {
        return $this->postJson('/api/auth/reset-password', [
            'token' => $code,
            'email' => $user->email,
            'password' => $password,
            'password_confirmation' => $password,
        ]);
    }
}
