<?php

namespace Database\Seeders;

use App\Models\Store;
use App\Models\User;
use Illuminate\Database\Console\Seeds\WithoutModelEvents;
use Illuminate\Database\Seeder;

class DatabaseSeeder extends Seeder
{
    use WithoutModelEvents;

    /**
     * Seed the application's database.
     */
    public function run(): void
    {
        $kira = Store::create([
            'name' => 'Kira (Main/Warehouse)',
            'code' => 'KIRA',
            'is_main' => true,
            'is_active' => true,
        ]);

        Store::create([
            'name' => 'Lugogo',
            'code' => 'LUGOGO',
            'is_main' => false,
            'is_active' => true,
        ]);

        Store::create([
            'name' => 'Town',
            'code' => 'TOWN',
            'is_main' => false,
            'is_active' => true,
        ]);

        User::factory()->create([
            'name' => 'Admin',
            'phone' => '0700000000',
            'email' => 'admin@cream.co.ug',
            'role' => User::ROLE_ADMIN,
            'store_id' => null,
        ]);
    }
}
