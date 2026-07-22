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

class DatabaseSeeder extends Seeder
{
    use WithoutModelEvents;

    /**
     * Seed the application's database.
     *
     * Every step here is safe to re-run: firstOrCreate/updateOrCreate skip
     * anything that already exists instead of failing on a duplicate key.
     * That matters in practice — a seed run that dies partway through
     * (e.g. on a since-fixed bug) previously left the database stuck
     * halfway seeded with no safe way to finish the job. `php artisan
     * db:seed` can now always be re-run to backfill whatever is missing.
     */
    public function run(): void
    {
        $kira = Store::firstOrCreate(
            ['code' => 'KIRA'],
            ['name' => 'Kira (Main/Warehouse)', 'is_main' => true, 'is_active' => true],
        );

        $lugogo = Store::firstOrCreate(
            ['code' => 'LUGOGO'],
            ['name' => 'Lugogo', 'is_main' => false, 'is_active' => true],
        );

        $town = Store::firstOrCreate(
            ['code' => 'TOWN'],
            ['name' => 'Town', 'is_main' => false, 'is_active' => true],
        );

        $stores = [$kira, $lugogo, $town];

        // Created directly (not via factory()) because factories always evaluate
        // fake() in definition(), and fakerphp/faker is a require-dev package
        // that isn't installed in the production image (composer install --no-dev).
        User::firstOrCreate(
            ['phone' => '0700000000'],
            [
                'name' => 'Admin',
                'email' => 'admin@cream.co.ug',
                'password' => 'password',
                'role' => User::ROLE_ADMIN,
                'store_id' => null,
                'is_active' => true,
            ],
        );

        if (! PlatePrice::query()->exists()) {
            PlatePrice::create([
                'store_id' => null,
                'price' => 25000,
                'effective_from' => now()->toDateString(),
                'is_active' => true,
            ]);
        }

        // Kitchen/stock items (not individually sold — they're what the
        // fixed-price plate is made from, tracked here purely for Stock
        // In/Out). Client-supplied list.
        foreach ([
            'Matooke', 'Karo', 'Rice', 'Posho', 'Pumpkin', 'Cassava',
            'Sweet Potatoes', 'Yam', 'Irish', 'Goat Stew', 'Chicken Stew',
            'Fresh Fish Stew', 'Fresh Beans With Ghee', 'Fresh Beans No Ghee',
            'Gnuts With Greens', 'Eshabwe',
        ] as $name) {
            $item = Item::firstOrCreate(
                ['name' => $name],
                ['unit' => 'kg', 'is_drink' => false, 'is_active' => true],
            );

            foreach ($stores as $store) {
                ItemStoreSetting::firstOrCreate(
                    ['item_id' => $item->id, 'store_id' => $store->id],
                    ['safety_stock' => 10],
                );
            }
        }

        // Each store stocks and sells its own drinks (bought locally, not
        // transferred from Kira). Client-supplied list.
        foreach ([
            ['name' => 'Passion Juice (No Sugar)', 'price' => 5000],
            ['name' => 'Passion Juice (With Sugar)', 'price' => 5000],
            ['name' => 'Cocktail (With Sugar)', 'price' => 5000],
            ['name' => 'Cocktail (No Sugar)', 'price' => 5000],
            ['name' => 'Bushera', 'price' => 5000],
            ['name' => 'Soda', 'price' => 2000],
            ['name' => 'Water', 'price' => 2000],
        ] as $drink) {
            $item = Item::firstOrCreate(
                ['name' => $drink['name']],
                ['unit' => 'bottle', 'is_drink' => true, 'is_active' => true],
            );

            DrinkPrice::firstOrCreate(
                ['item_id' => $item->id, 'store_id' => null],
                ['price' => $drink['price'], 'effective_from' => now()->toDateString(), 'is_active' => true],
            );

            foreach ($stores as $store) {
                ItemStoreSetting::firstOrCreate(
                    ['item_id' => $item->id, 'store_id' => $store->id],
                    ['safety_stock' => 10],
                );
            }
        }

        foreach ([
            ['name' => 'Standard', 'price_per_plate' => 34000],
            ['name' => 'Premium', 'price_per_plate' => 38000],
            ['name' => 'Deluxe', 'price_per_plate' => 45000],
        ] as $package) {
            CateringPackage::firstOrCreate(
                ['name' => $package['name']],
                ['price_per_plate' => $package['price_per_plate'], 'is_active' => true],
            );
        }
    }
}
