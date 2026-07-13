<?php

namespace Database\Factories;

use App\Models\CateringOrder;
use App\Models\CateringPackage;
use App\Models\User;
use Illuminate\Database\Eloquent\Factories\Factory;

/**
 * @extends Factory<CateringOrder>
 */
class CateringOrderFactory extends Factory
{
    public function definition(): array
    {
        return [
            'client_name' => fake()->name(),
            'client_phone' => fake()->numerify('07########'),
            'event_name' => fake()->randomElement(['Wedding', 'Graduation', 'Conference']),
            'event_date' => fake()->dateTimeBetween('now', '+2 months')->format('Y-m-d'),
            'catering_package_id' => CateringPackage::factory(),
            'number_of_plates' => 50,
            'total_amount' => 1700000,
            'status' => CateringOrder::STATUS_QUOTED,
            'created_by' => User::factory(),
        ];
    }
}
