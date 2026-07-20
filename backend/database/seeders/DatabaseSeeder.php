<?php

namespace Database\Seeders;

use App\Models\CateringPackage;
use App\Models\DrinkPrice;
use App\Models\Item;
use App\Models\ItemStoreSetting;
use App\Models\PlatePrice;
use App\Models\Store;
use App\Models\User;
use Illuminate\Database\Console\Seeds\WithoutModelEvents;
use Illuminate\Database\Seeder;
use Illuminate\Support\Facades\Hash;

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

        $lugogo = Store::create([
            'name' => 'Lugogo',
            'code' => 'LUGOGO',
            'is_main' => false,
            'is_active' => true,
        ]);

        $town = Store::create([
            'name' => 'Town',
            'code' => 'TOWN',
            'is_main' => false,
            'is_active' => true,
        ]);

        $stores = [$kira, $lugogo, $town];

        // Created directly (not via factory()) because factories always evaluate
        // fake() in definition(), and fakerphp/faker is a require-dev package
        // that isn't installed in the production image (composer install --no-dev).
        User::create([
            'name' => 'Admin',
            'phone' => '0700000000',
            'email' => 'admin@cream.co.ug',
            'password' => 'password',
            'role' => User::ROLE_ADMIN,
            'store_id' => null,
            'is_active' => true,
        ]);

        PlatePrice::create([
            'store_id' => null,
            'price' => 25000,
            'effective_from' => now()->toDateString(),
            'is_active' => true,
        ]);

        // Each store stocks and sells its own drinks (bought locally, not transferred from Kira).
        foreach ([
            ['name' => 'Passion Juice', 'price' => 5000],
            ['name' => 'Mocktail', 'price' => 5000],
            ['name' => 'Bushera', 'price' => 5000],
            ['name' => 'Soda', 'price' => 2000],
            ['name' => 'Water', 'price' => 2000],
            ['name' => 'Eshande', 'price' => 5000],
        ] as $drink) {
            $item = Item::create([
                'name' => $drink['name'],
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

            foreach ($stores as $store) {
                ItemStoreSetting::create([
                    'item_id' => $item->id,
                    'store_id' => $store->id,
                    'safety_stock' => 10,
                ]);
            }
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
