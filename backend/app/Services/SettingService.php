<?php

namespace App\Services;

use App\Repositories\Admin\AdminSettingRepository;
use App\Services\Admin\AdminSettingService;
use Illuminate\Support\Facades\Cache;

/**
 * Read access to stored settings for the rest of the application.
 *
 * Writes go through {@see AdminSettingService}; this class
 * is the one place consumers read from, so the cache lives here and nowhere
 * else. The whole key/value map is cached under a single key and dropped
 * whenever a setting is written, which keeps a read off the database on every
 * request without a per-key invalidation puzzle.
 *
 * Every accessor falls back to a caller-supplied default when the stored value
 * is missing, empty, malformed, or outside the bounds its registry entry
 * declares. That is deliberate: a bad setting must never be able to switch off a
 * business rule. A consumer that asks for the photo limit and gets garbage back
 * gets the code's own constant, not zero — and a stored `0` or negative, which
 * would otherwise read as a real ceiling, is treated the same way.
 */
class SettingService
{
    public const CACHE_KEY = 'settings.values';

    public function __construct(private readonly AdminSettingRepository $settings)
    {
        //
    }

    /**
     * Return the raw stored value for a key, or the supplied default.
     *
     * The registry default is used when no explicit default is given, so a
     * caller can always name the platform's documented fallback without
     * repeating it.
     */
    public function get(string $key, ?string $default = null): ?string
    {
        $value = $this->values()[$key] ?? null;

        if ($value !== null && $value !== '') {
            return $value;
        }

        if ($default !== null) {
            return $default;
        }

        $definition = config('settings.keys')[$key] ?? null;

        return $definition['default'] ?? null;
    }

    /**
     * Return a setting as a whole number, falling back on anything malformed or
     * outside the registry's bounds.
     */
    public function getInt(string $key, int $default): int
    {
        $value = $this->get($key);

        if ($value === null || ! preg_match('/^-?\d+$/', $value)) {
            return $default;
        }

        $number = (int) $value;

        return $this->withinBounds($key, (float) $number) ? $number : $default;
    }

    /**
     * Return a setting as a decimal, falling back on anything malformed or
     * outside the registry's bounds.
     */
    public function getDecimal(string $key, float $default): float
    {
        $value = $this->get($key);

        if ($value === null || ! is_numeric($value)) {
            return $default;
        }

        $number = (float) $value;

        return $this->withinBounds($key, $number) ? $number : $default;
    }

    /**
     * Whether a numeric stored value sits within its registry bounds.
     *
     * An unregistered key, or one whose entry declares no bounds, is
     * unconstrained. An out-of-range value is treated exactly like a malformed
     * one by the accessors above: the caller's default wins. That is what stops
     * a stored `0` from turning a photo ceiling into "no photos" and a stored
     * negative from turning a price ceiling into "no listings".
     */
    private function withinBounds(string $key, float $number): bool
    {
        $definition = config('settings.keys')[$key] ?? null;

        if ($definition === null) {
            return true;
        }

        if (isset($definition['min']) && $number < (float) $definition['min']) {
            return false;
        }

        if (isset($definition['max']) && $number > (float) $definition['max']) {
            return false;
        }

        return true;
    }

    /**
     * Drop the cached map. Called after any settings write.
     */
    public function flush(): void
    {
        Cache::forget(self::CACHE_KEY);
    }

    /**
     * The full key => value map, cached.
     *
     * @return array<string, string>
     */
    private function values(): array
    {
        return Cache::rememberForever(
            self::CACHE_KEY,
            fn (): array => $this->settings->all()
                ->mapWithKeys(fn ($setting): array => [$setting->key => (string) $setting->value])
                ->all(),
        );
    }
}
