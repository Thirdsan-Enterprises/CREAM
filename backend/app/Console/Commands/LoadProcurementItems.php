<?php

namespace App\Console\Commands;

use App\Models\Item;
use App\Models\ItemStoreSetting;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\DB;

/**
 * Loads the procurement list Cream wrote out (November 2026): what the
 * procurement unit buys and sends to the branches, grouped so it is easy
 * to find. Safe to run again. Procurement and the owner can add, rename or
 * remove items in the app afterwards.
 *
 *   php artisan cream:load-procurement-items
 */
class LoadProcurementItems extends Command
{
    protected $signature = 'cream:load-procurement-items';

    protected $description = 'Load the procurement (kitchen stock) list';

    /** [category, name, unit, other names it may already have] */
    public const ITEMS = [
        ['Food', 'Sugar', 'kg', []],
        ['Food', 'Salt', 'kg', []],
        ['Food', 'Cooking oil', 'litre', []],
        ['Food', 'Baking powder', 'packet', []],
        ['Food', 'Eggs', 'tray', []],
        ['Food', 'Milk', 'litre', []],
        ['Food', 'Coffee', 'packet', []],
        ['Food', 'Chocolate', 'packet', []],
        ['Food', 'Fruits', 'kg', []],
        ['Food', 'Watermelon', 'piece', []],
        ['Food', 'Yams', 'kg', ['Yam']],
        ['Food', 'Sweet potatoes', 'kg', ['Sweet Potatoes']],
        ['Food', 'Irish potatoes', 'kg', ['Irish']],
        ['Food', 'Cassava', 'kg', []],

        ['Spices & seasoning', 'Aromat', 'packet', []],
        ['Spices & seasoning', 'Royco', 'packet', []],
        ['Spices & seasoning', 'Beef masala', 'packet', []],
        ['Spices & seasoning', 'Chicken masala', 'packet', []],
        ['Spices & seasoning', 'Soy sauce', 'bottle', []],
        ['Spices & seasoning', 'Oregano', 'packet', []],

        ['Packaging & disposables', 'Serviettes', 'packet', []],
        ['Packaging & disposables', 'Toothpicks', 'packet', []],
        ['Packaging & disposables', 'Silver plates', 'piece', []],
        ['Packaging & disposables', 'Disposable forks', 'packet', []],
        ['Packaging & disposables', 'Disposable spoons', 'packet', []],
        ['Packaging & disposables', 'Packing bags', 'packet', []],
        ['Packaging & disposables', 'Polythene bags (obuveera)', 'packet', []],
        ['Packaging & disposables', 'Cling film', 'roll', []],
        ['Packaging & disposables', 'Foil paper', 'roll', []],

        ['Cleaning', 'Hand wash', 'bottle', []],
        ['Cleaning', 'Soap', 'bar', []],
        ['Cleaning', 'Steel wire', 'piece', []],

        ['Fuel', 'Gas', 'cylinder', []],
        ['Fuel', 'Charcoal', 'bag', []],
    ];

    /** Kitchen items already in the system, put under a heading too. */
    public const EXISTING = [
        'Matooke' => 'Food', 'Karo' => 'Food', 'Rice' => 'Food', 'Posho' => 'Food', 'Pumpkin' => 'Food',
    ];

    /**
     * Items that turned out to be something else: mineral water is the
     * bottled Water drink, which each branch buys and sells itself.
     */
    public const RETIRED = ['Mineral water'];

    public function handle(): int
    {
        $added = 0;
        DB::transaction(function () use (&$added) {
            foreach (self::ITEMS as [$category, $name, $unit, $aliases]) {
                // Kitchen stock only: never the menu dish of the same name.
                $item = Item::where('is_sellable', false)->where('tracks_stock', true)
                    ->whereIn('name', [$name, ...$aliases])->first();
                if ($item) {
                    $item->update(['name' => $name, 'category' => $category, 'is_active' => true]);
                } else {
                    $item = Item::create([
                        'name' => $name, 'unit' => $unit, 'category' => $category,
                        'is_drink' => false, 'is_sellable' => false, 'tracks_stock' => true, 'is_active' => true,
                    ]);
                    $added++;
                }
                ItemStoreSetting::backfillForItem($item);
            }
            foreach (Item::where('is_sellable', false)->where('is_drink', false)->whereIn('name', self::RETIRED)->get() as $item) {
                $used = DB::table('stock_movements')->where('item_id', $item->id)->exists()
                    || DB::table('stock_transfer_items')->where('item_id', $item->id)->exists()
                    || DB::table('stock_request_items')->where('item_id', $item->id)->exists();
                $used ? $item->update(['is_active' => false]) : $item->delete();
            }
            foreach (self::EXISTING as $name => $category) {
                Item::where('name', $name)->where('is_sellable', false)->whereNull('category')->update(['category' => $category]);
            }
        });

        $this->info(count(self::ITEMS)." procurement items in place ({$added} new).");

        return self::SUCCESS;
    }
}
