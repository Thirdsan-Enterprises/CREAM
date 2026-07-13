<?php

namespace Database\Factories;

use App\Models\Store;
use Illuminate\Database\Eloquent\Factories\Factory;

/**
 * @extends Factory<Store>
 */
class StoreFactory extends Factory
{
    public function definition(): array
    {
        return [
            'name' => fake()->unique()->city(),
            'code' => strtoupper(fake()->unique()->lexify('???')),
            'is_main' => false,
            'address' => fake()->address(),
            'phone' => fake()->numerify('07########'),
            'is_active' => true,
        ];
    }
}
