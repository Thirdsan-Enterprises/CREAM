<?php

namespace Database\Factories;

use App\Models\Item;
use Illuminate\Database\Eloquent\Factories\Factory;

/**
 * @extends Factory<Item>
 */
class ItemFactory extends Factory
{
    public function definition(): array
    {
        return [
            'name' => fake()->unique()->word(),
            'unit' => fake()->randomElement(['kg', 'litre', 'piece', 'crate', 'bottle']),
            'category' => null,
            'is_drink' => false,
            'is_active' => true,
        ];
    }
}
