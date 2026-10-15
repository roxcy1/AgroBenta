<?php

namespace Database\Factories;

use App\Enums\ActivityAction;
use App\Models\Activity;
use App\Models\User;
use DateTimeInterface;
use Illuminate\Database\Eloquent\Factories\Factory;

/**
 * @extends Factory<Activity>
 */
class ActivityFactory extends Factory
{
    /**
     * Define the model's default state.
     *
     * @return array<string, mixed>
     */
    public function definition(): array
    {
        return [
            'user_id' => User::factory(),
            'action' => fake()->randomElement(ActivityAction::cases())->value,
            'description' => fake()->sentence(),
            'metadata' => null,
        ];
    }

    /**
     * Place the entry at a controlled instant.
     *
     * Audit entries are only meaningful relative to time, so a test needs to
     * backdate one. Laravel writes factory attributes inside a
     * `Model::unguarded` window, so the timestamp lands even though
     * `created_at` is deliberately not fillable on the model.
     */
    public function createdAt(DateTimeInterface $timestamp): static
    {
        return $this->state(fn (array $attributes) => [
            'created_at' => $timestamp,
            'updated_at' => $timestamp,
        ]);
    }
}
