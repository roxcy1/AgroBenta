<?php

namespace App\Models;

// use Illuminate\Contracts\Auth\MustVerifyEmail;
use App\Enums\SellerCapability;
use App\Enums\UserRole;
use Database\Factories\UserFactory;
use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Attributes\Hidden;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Database\Eloquent\Relations\HasOne;
use Illuminate\Database\Eloquent\SoftDeletes;
use Illuminate\Foundation\Auth\User as Authenticatable;
use Illuminate\Notifications\Notifiable;
use Laravel\Sanctum\HasApiTokens;

#[Fillable([
    'name', 'email', 'password',
    'phone', 'location', 'avatar_url', 'bio',
])]
#[Hidden(['password', 'remember_token'])]
class User extends Authenticatable
{
    /** @use HasFactory<UserFactory> */
    use HasApiTokens, HasFactory, Notifiable, SoftDeletes;

    /**
     * Get the attributes that should be cast.
     *
     * @return array<string, string>
     */
    protected function casts(): array
    {
        return [
            'email_verified_at' => 'datetime',
            'password' => 'hashed',
            'role' => UserRole::class,
            'seller_capability' => SellerCapability::class,
        ];
    }

    public function isAdmin(): bool
    {
        return $this->role === UserRole::Admin;
    }

    public function isAdminSeller(): bool
    {
        return $this->isAdmin() && $this->seller_capability === SellerCapability::Seller;
    }

    public function isApprovedSeller(): bool
    {
        return $this->seller_capability === SellerCapability::Seller;
    }

    /**
     * Whether this account is currently eligible to be presented as a verified
     * seller in a public mobile projection.
     */
    public function isVerifiedSeller(): bool
    {
        return $this->isApprovedSeller() && ! $this->trashed();
    }

    /**
     * The phones registered for push notifications.
     */
    public function deviceTokens(): HasMany
    {
        return $this->hasMany(DeviceToken::class);
    }

    /**
     * The push switches from Notification Settings; null means all on.
     */
    public function notificationPreference(): HasOne
    {
        return $this->hasOne(NotificationPreference::class);
    }

    public function sellerVerifications(): HasMany
    {
        return $this->hasMany(SellerVerification::class);
    }

    public function listings(): HasMany
    {
        return $this->hasMany(Listing::class, 'seller_id');
    }

    public function transactionsAsBuyer(): HasMany
    {
        return $this->hasMany(Transaction::class, 'buyer_id');
    }

    public function transactionsAsSeller(): HasMany
    {
        return $this->hasMany(Transaction::class, 'seller_id');
    }

    public function activities(): HasMany
    {
        return $this->hasMany(Activity::class);
    }

    public function sentMessages(): HasMany
    {
        return $this->hasMany(Message::class, 'sender_id');
    }

    public function receivedMessages(): HasMany
    {
        return $this->hasMany(Message::class, 'receiver_id');
    }

    /**
     * Reports this account filed against other users.
     */
    public function sentReports(): HasMany
    {
        return $this->hasMany(UserReport::class, 'reporter_id');
    }

    /**
     * Reports other users filed against this account.
     */
    public function receivedReports(): HasMany
    {
        return $this->hasMany(UserReport::class, 'reported_user_id');
    }

    /**
     * The administrator who last deactivated this account.
     */
    public function deactivatedBy(): BelongsTo
    {
        return $this->belongsTo(self::class, 'deactivated_by')->withTrashed();
    }
}
