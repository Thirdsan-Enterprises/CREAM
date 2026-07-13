<?php

namespace Database\Seeders;

use App\Models\CateringPackage;
use App\Models\DrinkPrice;
use App\Models\Item;
use App\Models\PlatePrice;
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

        PlatePrice::create([
            'store_id' => null,
            'price' => 25000,
            'effective_from' => now()->toDateString(),
            'is_active' => true,
        ]);

        // Prices/costs below are placeholders (TBC) pending final figures from the client.
        foreach ([
            ['name' => 'Soda', 'price' => 3000],
            ['name' => 'Water', 'price' => 2000],
            ['name' => 'Juice', 'price' => 4000],
        ] as $drink) {
            $item = Item::create([
                'name' => $drink['name'].' (TBC)',
                'unit' => 'bottle',
                'is_drink' => true,
                'is_active' => true,
            ]);

            DrinkPrice::create([
                'item_id' => $item->id,
                'store_id' => null,
                'price' => $drink['price'],
                'effective_from' => now()->toDateString(),
                'is_active' => true,
            ]);
        }

        foreach ([
            ['name' => 'Standard', 'price_per_plate' => 34000],
            ['name' => 'Premium', 'price_per_plate' => 38000],
            ['name' => 'Deluxe', 'price_per_plate' => 45000],
        ] as $package) {
            CateringPackage::create([
                'name' => $package['name'],
                'price_per_plate' => $package['price_per_plate'],
                'is_active' => true,
            ]);
        }
    }
}
