<?php

namespace App\Providers;

use App\Auth\PasswordResetCodeBrokerManager;
use App\Contracts\PriceSuggestionProvider;
use App\Events\NotificationCreated;
use App\Models\User;
use App\Services\PriceSuggestion\FastApiPriceSuggestionProvider;
use Illuminate\Auth\Notifications\ResetPassword;
use Illuminate\Notifications\Events\NotificationSent;
use Illuminate\Notifications\Messages\MailMessage;
use Illuminate\Support\Facades\Event;
use Illuminate\Support\ServiceProvider;

class AppServiceProvider extends ServiceProvider
{
    /**
     * Register any application services.
     */
    public function register(): void
    {
        $this->app->extend('auth.password', fn ($manager, $app) => new PasswordResetCodeBrokerManager($app));

        $this->app->bind(PriceSuggestionProvider::class, FastApiPriceSuggestionProvider::class);
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

        // Real-time: after a database notification is stored, broadcast it to
        // the recipient's private channel so the mobile badge updates live.
        // This covers notifications with no domain event of their own (e.g.
        // admin approval of a listing or a seller verification). Non-database
        // channels (mail) are ignored: the mobile client reads the database.
        Event::listen(NotificationSent::class, function (NotificationSent $event): void {
            if ($event->channel !== 'database') {
                return;
            }

            if ($event->notifiable instanceof User) {
                NotificationCreated::dispatch($event->notifiable, $event->notification);
            }
        });
    }
}
