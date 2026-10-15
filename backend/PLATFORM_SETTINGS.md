# Platform Settings — Implementation

How configurable platform settings are stored, validated, and (where applicable)
consumed at runtime.

## Registry

`config/settings.php` is the single source of truth for every supported setting.
Each entry defines its presentation metadata (`group`, `label`, `description`),
its validation (`type`, `required`, `min`/`max`, `max_length`) and its `default`.

The `settings` table is row-based (`key` / `value`), so **adding a setting is a
registry + seeder change only — no schema change**. Values are stored as text;
each entry's `default` mirrors that stored form.

`SettingService` reads values through a cached `settings.values` map and is
flushed by `AdminSettingService::updateSettings()` whenever settings change.

### Fallback behavior

`SettingService::getInt()` / `getDecimal()` return the caller-supplied default
when the stored value is **missing, malformed, or outside the registry's
`min`/`max` bounds** (`withinBounds()`). A missing or bad value therefore can
never disable enforcement — the consumer always gets a safe value.

## Runtime-read settings

These settings are consumed by real application behavior. Changing the value
changes actual enforcement (not only the displayed form).

| Setting | Consumer | Bounds | Default |
|---|---|---|---|
| `listing.max_photos` | `SellerListingRules::photoLimit()` (`app/Http/Requests/SellerListing/SellerListingRules.php:98`), used by the create/update/submission rules and by `StoreListingPhotoRequest::rules()` (`app/Http/Requests/SellerListing/StoreListingPhotoRequest.php:38`); also `SellerListingService::addPhotos()` via the `SellerListingRules` trait | integer, 1–50 | `10` (falls back to `Listing::PHOTO_LIMIT`) |
| `listing.max_price` | `SellerListingRules::maxAskingPrice()` (`app/Http/Requests/SellerListing/SellerListingRules.php:109`) | decimal, 0.01–99999999999.99 | `99999999999.99` (the `decimal(14,2)` column maximum) |

The backend is authoritative: the limits are applied server-side in Form Request
validation regardless of what any client sends.

## Stored-but-unused settings

These settings persist, are editable through the admin settings page, and are
validated, but have **no verified runtime consumer** in the current codebase.

| Setting | Bounds | Default |
|---|---|---|
| `system.name` | string, required, ≤255 | `AgroBenta` |
| `system.description` | text, ≤1000 | `A livestock trading platform connecting buyers and sellers.` |
| `admin_contact.name` | string, ≤255 | `Administrator` |
| `admin_contact.email` | email, ≤255 | `admin@agrobenta.example.com` |
| `admin_contact.phone` | string, ≤50 | *(empty)* |
| `verification.guidance` | text, ≤2000 | *(empty)* |

## Blocked consumers

The following intended consumers cannot be wired without an approved public /
mobile API contract. The mobile app must not call admin endpoints, and the
mobile contract is still a proposal (`docs/MOBILE_API_CONTRACT_PROPOSAL.md`,
status: NOT APPROVED — see `docs/AGENTS.md`).

- **`verification.guidance`** — described as "Guidance shown to sellers when
  submitting verification", but the mobile seller-verification flow has no
  consumer for it and no public endpoint exposes it.
- **Client-side listing limits** — the mobile seller create/edit flow validates
  against a hardcoded constant, `kListingMaxAskingPrice = '99999999999.99'`
  (`mobile/lib/features/seller_listings/view/seller_listing_validators.dart:23`),
  not the configured `listing.max_price`. Exposing the effective limit to mobile
  requires a new public endpoint that is not currently approved.

## Validation

Server-side validation lives in
`app/Http/Requests/Admin/UpdateSettingsRequest.php` (types, required values, and
`min`/`max` bounds). By the time a request reaches
`AdminSettingService::updateSettings()`, invalid values have already been
rejected with `422`, so an invalid update cannot partially persist;
`AdminSettingRepository::updateMany()` additionally writes within a single
`DB::transaction`.

Covering tests:

- `tests/Feature/Admin/SettingsTest.php`
- `tests/Feature/SellerListing/SellerListingPhotoTest.php`
- `tests/Feature/SellerListing/MobileSellerListingTest.php`
