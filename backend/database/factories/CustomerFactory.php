<?php

namespace Database\Factories;

use App\Models\Customer;
use App\Models\User;
use Illuminate\Database\Eloquent\Factories\Factory;

/**
 * @extends Factory<Customer>
 */
class CustomerFactory extends Factory
{
    public function definition(): array
    {
        return [
            'name' => fake()->name(),
            'phone' => fake()->unique()->numerify('07########'),
            'account_type' => Customer::TYPE_PREPAID,
            'credit_limit' => 0,
            'is_active' => true,
            'created_by' => User::factory(),
        ];
    }

    public function credit(float $limit = 100000): self
    {
        return $this->state(fn () => [
            'account_type' => Customer::TYPE_CREDIT,
            'credit_limit' => $limit,
        ]);
    }
}
