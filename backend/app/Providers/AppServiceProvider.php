<?php

namespace App\Providers;

use App\Auth\PasswordResetCodeBrokerManager;
use Illuminate\Auth\Notifications\ResetPassword;
use Illuminate\Notifications\Messages\MailMessage;
use Illuminate\Support\ServiceProvider;

class AppServiceProvider extends ServiceProvider
{
    /**
     * Register any application services.
     */
    public function register(): void
    {
        $this->app->extend('auth.password', fn ($manager, $app) => new PasswordResetCodeBrokerManager($app));
    }

    /**
     * Bootstrap any application services.
     */
    public function boot(): void
    {
        // Replaces Laravel's default email, which links to a `password.reset`
        // web route this API does not have and would fail when sent.
        ResetPassword::toMailUsing(function ($notifiable, string $code): MailMessage {
            $broker = config('auth.defaults.passwords');

            return (new MailMessage)
                ->subject('Your AgroBenta password reset code')
                ->line('Enter this code in the AgroBenta app to reset your password:')
                ->line($code)
                ->line('The code expires in '.config("auth.passwords.{$broker}.expire").' minutes.')
                ->line('If you did not ask to reset your password, you can ignore this email.');
        });
    }
}
