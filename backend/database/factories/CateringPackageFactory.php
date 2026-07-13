<?php

namespace Database\Factories;

use App\Models\CateringPackage;
use Illuminate\Database\Eloquent\Factories\Factory;

/**
 * @extends Factory<CateringPackage>
 */
class CateringPackageFactory extends Factory
{
    public function definition(): array
    {
        return [
            'name' => fake()->randomElement(['Standard', 'Premium', 'Deluxe']),
            'price_per_plate' => fake()->randomElement([34000, 38000, 45000]),
            'description' => null,
            'is_active' => true,
        ];
    }
}
