<?php

namespace App\Console\Commands;

use App\Models\DrinkPrice;
use App\Models\Item;
use App\Models\ItemStoreSetting;
use App\Models\Store;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\DB;

/**
 * Loads the menu Cream sent (November 2026) for Town and Kira, which share
 * one menu. Safe to run again: existing items keep their stock and history,
 * prices are only set where none is set yet unless --update-prices is given.
 *
 *   php artisan cream:load-menu
 */
class LoadMenu extends Command
{
    protected $signature = 'cream:load-menu
        {--branches=TOWN,KIRA : Codes of the branches that sell this menu}
        {--update-prices : Also overwrite prices already set at those branches}';

    protected $description = 'Load the Town/Kira breakfast and lunch menu';

    /** Every lunch at Kira is this price (a Kira price on each dish). */
    public const KIRA_LUNCH_PRICE = 25000;

    /**
     * Lugogo's own lunches, sold only there: [name, price, earlier name].
     * Kept apart from Town/Kira's Beef so the owner can rename or reprice
     * Lugogo's without touching the other branches.
     */
    public const LUGOGO_LUNCH = [
        ['Beef', 15000, 'Full plate'],
        ['Beans', 10000, 'Small plate'],
    ];

    /** Charged on top when food is packed to take away, at every branch. */
    public const EVERY_BRANCH = [
        ['Takeaway', 'Silver plate', 500],
    ];

    /** [heading, name, unit, price, counted on a shelf] */
    public const MENU = [
        ['Lunch', 'Beef', 'plate', 10000, false],
        ['Lunch', 'Fish', 'plate', 12000, false],
        ['Lunch', 'Chicken', 'plate', 12000, false],
        ['Lunch', 'Goat', 'plate', 12000, false],
        ['Lunch', 'Peas', 'plate', 9000, false],
        ['Lunch', 'Beans / G.nuts', 'plate', 8000, false],
        ['Lunch', 'Mulokoni', 'plate', 8000, false],

        ['Breakfast', 'Milk Tea', 'cup', 3000, false],
        ['Breakfast', 'Black Tea', 'cup', 3000, false],
        ['Breakfast', 'Mandazi', 'piece', 1000, false],
        ['Breakfast', 'Chapati', 'piece', 1500, false],
        ['Breakfast', 'Gonja', 'piece', 1000, false],
        ['Breakfast', 'Samosa (Meat)', 'piece', 1500, false],
        ['Breakfast', 'Samosa (Chicken)', 'piece', 1500, false],
        ['Breakfast', 'Samosa (Vegetable)', 'piece', 1000, false],
        ['Breakfast', 'Bun', 'piece', 1000, false],
        ['Breakfast', 'Cake', 'piece', 1500, false],
        ['Breakfast', 'Sweet Potatoes', 'portion', 1000, false],
        ['Breakfast', 'Cassava', 'portion', 500, false],
        ['Breakfast', 'Katogo', 'plate', 5000, false],
        ['Breakfast', 'Yam', 'portion', 1000, false],
        ['Breakfast', 'Egg', 'piece', 500, false],
        ['Breakfast', 'Rolex', 'piece', 5000, false],
        ['Breakfast', 'Banana', 'piece', 500, false],
        ['Breakfast', 'Sausage', 'piece', 1500, false],
        ['Breakfast', 'Omelette', 'plate', 3000, false],
        ['Breakfast', 'Pancake', 'piece', 500, false],
        ['Takeaway', 'Silver plate', 'piece', 500, false],

        ['Drinks', 'Minute Maid', 'bottle', 3000, true],
        ['Drinks', 'Water', 'bottle', 1500, true],
        ['Drinks', 'Soda', 'bottle', 1500, true],
    ];

    public function handle(): int
    {
        $codes = array_filter(array_map('trim', explode(',', strtoupper((string) $this->option('branches')))));
        $branches = Store::whereIn(DB::raw('UPPER(code)'), $codes)->get();
        if ($branches->count() !== count($codes)) {
            $this->error('Unknown branch code. Branches: '.Store::pluck('code')->join(', '));

            return self::FAILURE;
        }
        $others = Store::whereNotIn('id', $branches->pluck('id'))->get();

        DB::transaction(function () use ($branches, $others) {
            foreach (self::MENU as [$heading, $name, $unit, $price, $counted]) {
                // Reuse a menu item (or drink) of the same name, never a
                // kitchen stock item: "Cassava" on the breakfast menu is a
                // dish, not the kilos of cassava procurement buys.
                $item = Item::where('name', $name)
                    ->where(fn ($q) => $q->where('is_sellable', true)->orWhere('is_drink', true))
                    ->whereNotIn('id', $this->lugogoOwnIds())
                    ->orderBy('id')
                    ->first()
                    ?? Item::create([
                        'name' => $name,
                        'unit' => $unit,
                        'is_active' => true,
                        'is_drink' => $heading === 'Drinks',
                        // Lunch is plates counted per day (Today's plates).
                        'tracks_stock' => $counted || $heading === 'Lunch',
                        'daily_stock' => $heading === 'Lunch',
                    ]);
                $isNew = $item->wasRecentlyCreated;
                $item->update([
                    'is_sellable' => true,
                    'sell_category' => $heading,
                    'is_active' => true,
                ]);
                ItemStoreSetting::backfillForItem($item);

                // Drinks were already sold everywhere; a new dish is only on
                // this menu's branches.
                if ($isNew && $heading !== 'Drinks') {
                    ItemStoreSetting::where('item_id', $item->id)->whereIn('store_id', $others->pluck('id'))->update(['on_menu' => false]);
                }
                ItemStoreSetting::where('item_id', $item->id)->whereIn('store_id', $branches->pluck('id'))->update(['on_menu' => true]);

                foreach ($branches as $branch) {
                    $branchPrice = strtoupper($branch->code) === 'KIRA' && $heading === 'Lunch'
                        ? self::KIRA_LUNCH_PRICE
                        : $price;
                    $this->setBranchPrice($item, $branch->id, $branchPrice);
                }
                $this->line(sprintf('  %-10s %-20s UGX %s', $heading, $name, number_format($price)));

            }

            $this->loadLugogo();
            $this->loadEveryBranch();
        });

        $this->info(count(self::MENU).' menu items loaded for '.$branches->pluck('name')->join(' and ').' (lunch at Kira UGX '.number_format(self::KIRA_LUNCH_PRICE).').');

        return self::SUCCESS;
    }

    /** A branch's own price, unless one is set already (or --update-prices). */
    private function setBranchPrice(Item $item, int $storeId, float $price): void
    {
        $current = DrinkPrice::where('item_id', $item->id)->where('store_id', $storeId)->where('is_active', true)->first();
        if ($current && ((float) $current->price === $price || ! $this->option('update-prices'))) {
            return;
        }
        DrinkPrice::where('item_id', $item->id)->where('store_id', $storeId)->where('is_active', true)->update(['is_active' => false]);
        DrinkPrice::create([
            'item_id' => $item->id,
            'store_id' => $storeId,
            'price' => $price,
            'effective_from' => now()->toDateString(),
            'is_active' => true,
        ]);
    }

    private ?Store $lugogo = null;

    private function lugogo(): ?Store
    {
        return $this->lugogo ??= Store::where(DB::raw('UPPER(code)'), 'LUGOGO')->first();
    }

    /** Menu items sold at Lugogo and nowhere else. */
    private function lugogoOwnIds(): array
    {
        $lugogo = $this->lugogo();
        if (! $lugogo) {
            return [];
        }

        return ItemStoreSetting::where('on_menu', true)->get()
            ->groupBy('item_id')
            ->filter(fn ($rows) => $rows->pluck('store_id')->all() === [$lugogo->id])
            ->keys()->all();
    }

    /** Lugogo's lunches, only at Lugogo. */
    private function loadLugogo(): void
    {
        $lugogo = $this->lugogo();
        if (! $lugogo) {
            return;
        }
        $own = Item::where('is_sellable', true)->whereIn('id', $this->lugogoOwnIds());
        // Once Lugogo has lunches of its own the owner manages them in the
        // app; only the names of an earlier load are brought up to date.
        $fresh = ! (clone $own)->where('sell_category', 'Lunch')->exists();
        foreach (self::LUGOGO_LUNCH as [$name, $price, $earlier]) {
            $item = (clone $own)->where('name', $earlier)->first();
            if ($item && ! (clone $own)->where('name', $name)->exists()) {
                $item->update(['name' => $name]);
            } elseif ($fresh) {
                $item = Item::create([
                    'name' => $name, 'unit' => 'plate', 'is_active' => true, 'is_drink' => false,
                    'is_sellable' => true, 'sell_category' => 'Lunch', 'tracks_stock' => true, 'daily_stock' => true,
                ]);
                ItemStoreSetting::backfillForItem($item);
                ItemStoreSetting::where('item_id', $item->id)->where('store_id', '!=', $lugogo->id)->update(['on_menu' => false]);
                ItemStoreSetting::where('item_id', $item->id)->where('store_id', $lugogo->id)->update(['on_menu' => true]);
            } else {
                continue;
            }
            $this->setBranchPrice($item, $lugogo->id, $price);
            $this->line(sprintf('  %-10s %-20s UGX %s (Lugogo)', 'Lunch', $name, number_format($price)));
        }
    }

    /** Things like the takeaway silver plate, sold at every branch. */
    private function loadEveryBranch(): void
    {
        foreach (self::EVERY_BRANCH as [$heading, $name, $price]) {
            $item = Item::where('name', $name)->where('is_sellable', true)->orderBy('id')->first();
            if (! $item) {
                continue;
            }
            $item->update(['sell_category' => $heading]);
            foreach (Store::where('is_active', true)->get() as $store) {
                ItemStoreSetting::where('item_id', $item->id)->where('store_id', $store->id)->update(['on_menu' => true]);
                $this->setBranchPrice($item, $store->id, $price);
            }
        }
    }
}
