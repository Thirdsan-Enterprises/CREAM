<?php

namespace App\Http\Controllers;

use App\Models\DrinkPrice;
use App\Models\EditLog;
use App\Models\Item;
use App\Models\ItemStoreSetting;
use App\Models\Store;
use App\Services\PricingService;
use App\Services\StockService;
use App\Support\StoreScope;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\ValidationException;

/**
 * What can be sold on its own besides a plate: drinks, breakfast items such
 * as eggs and tea, anything the owner puts on the menu. Each has a price for
 * all branches and may have its own price at a branch.
 */
class MenuController extends Controller
{
    public function __construct(
        private readonly PricingService $pricingService,
        private readonly StockService $stockService,
    ) {}

    /** The menu at a branch: price, and how many are left if it tracks stock. */
    public function index(Request $request)
    {
        $storeId = StoreScope::resolve($request->user(), $request->integer('store_id') ?: null);

        $items = Item::query()
            ->where('is_active', true)
            ->where(fn ($q) => $q->where('is_sellable', true)->orWhere('is_drink', true))
            // Only what this branch sells.
            ->when($storeId, fn ($q) => $q->whereDoesntHave(
                'storeSettings',
                fn ($s) => $s->where('store_id', $storeId)->where('on_menu', false),
            ))
            ->orderBy('name')
            ->get()
            ->sortBy(fn (Item $item) => [self::headingOrder($item), $item->name])
            ->values();

        return $items->map(fn (Item $item) => [
            'item' => $item,
            'category' => $item->sell_category ?? ($item->is_drink ? 'Drinks' : 'Other'),
            'price' => $this->pricingService->currentItemPrice($item->id, $storeId),
            'tracks_stock' => (bool) $item->tracks_stock,
            'daily_stock' => (bool) $item->daily_stock,
            'balance' => $storeId && $item->tracks_stock
                ? $this->stockService->balance($item->id, $storeId)
                : null,
        ])->values();
    }

    /** Lunch first, then breakfast, drinks, and any other headings. */
    public static function headingOrder(Item $item): int
    {
        $heading = strtolower($item->sell_category ?? ($item->is_drink ? 'drinks' : 'other'));

        return match ($heading) {
            'lunch' => 0,
            'breakfast' => 1,
            'drinks' => 2,
            default => 3,
        };
    }

    /**
     * The branches that sell an item: null means every branch.
     *
     * @param  array<int>|null  $storeIds
     */
    private function setBranches(Item $item, ?array $storeIds): void
    {
        ItemStoreSetting::backfillForItem($item);
        ItemStoreSetting::where('item_id', $item->id)->update(['on_menu' => true]);
        if ($storeIds !== null) {
            ItemStoreSetting::where('item_id', $item->id)->whereNotIn('store_id', $storeIds)->update(['on_menu' => false]);
        }
    }

    /**
     * Put an item on the menu: a new one, or an item already in stock (for
     * example eggs bought for the kitchen that are now also sold on their own).
     */
    public function store(Request $request)
    {
        $data = $request->validate([
            'item_id' => ['nullable', 'exists:items,id'],
            'name' => ['required_without:item_id', 'nullable', 'string', 'max:255'],
            'unit' => ['nullable', 'string', 'max:50'],
            'category' => ['required', 'string', 'max:50'],
            'price' => ['required', 'numeric', 'gt:0'],
            'store_id' => ['nullable', 'exists:stores,id'],
            'tracks_stock' => ['sometimes', 'boolean'],
            'daily_stock' => ['sometimes', 'boolean'],
            'safety_stock' => ['nullable', 'numeric', 'min:0'],
            'branches' => ['nullable', 'array'],
            'branches.*' => ['integer', 'exists:stores,id'],
        ]);

        $item = DB::transaction(function () use ($data) {
            $category = trim($data['category']);
            $attributes = [
                'is_sellable' => true,
                'sell_category' => $category,
                // Counted per day (plates) implies counted.
                'daily_stock' => $data['daily_stock'] ?? false,
                'tracks_stock' => ($data['daily_stock'] ?? false) || ($data['tracks_stock'] ?? true),
                // A drink is bought by each branch itself; other items come
                // from the procurement unit.
                'is_drink' => strcasecmp($category, 'Drinks') === 0,
                'is_active' => true,
            ];

            if (! empty($data['item_id'])) {
                $item = Item::findOrFail($data['item_id']);
                if ($item->is_sellable) {
                    throw ValidationException::withMessages(['item_id' => ["{$item->name} is already on the menu."]]);
                }
                $item->update($attributes);
            } else {
                $item = Item::create([
                    'name' => trim($data['name']),
                    'unit' => $data['unit'] ?? 'piece',
                    ...$attributes,
                ]);
            }

            ItemStoreSetting::backfillForItem($item, (float) ($data['safety_stock'] ?? 0));
            $this->setBranches($item, $data['branches'] ?? null);
            $this->setPrice($item, (float) $data['price'], $data['store_id'] ?? null);

            return $item;
        });

        return response()->json($this->row($item, $data['store_id'] ?? null), 201);
    }

    /**
     * Change a menu item's details, or its price for all branches or one.
     * "use_default" with a store_id removes that branch's own price. A reason
     * is required, and the change is logged.
     */
    public function update(Request $request, Item $item)
    {
        $data = $request->validate([
            'name' => ['sometimes', 'string', 'max:255'],
            'unit' => ['sometimes', 'string', 'max:50'],
            'category' => ['sometimes', 'string', 'max:50'],
            'tracks_stock' => ['sometimes', 'boolean'],
            'daily_stock' => ['sometimes', 'boolean'],
            'is_active' => ['sometimes', 'boolean'],
            'price' => ['sometimes', 'numeric', 'gt:0'],
            'store_id' => ['nullable', 'exists:stores,id'],
            'use_default' => ['sometimes', 'boolean'],
            'branches' => ['sometimes', 'nullable', 'array'],
            'branches.*' => ['integer', 'exists:stores,id'],
            'reason' => ['required', 'string', 'max:500'],
        ], [
            'reason.required' => 'Say why this is changing.',
        ]);

        $storeId = $data['store_id'] ?? null;
        $useDefault = (bool) ($data['use_default'] ?? false);
        if ($useDefault && $storeId === null) {
            throw ValidationException::withMessages(['store_id' => ['Choose the branch to put back on the price for all branches.']]);
        }

        DB::transaction(function () use ($item, $data, $storeId, $useDefault, $request) {
            $before = [
                'name' => $item->name,
                'unit' => $item->unit,
                'category' => $item->sell_category,
                'tracks_stock' => (bool) $item->tracks_stock,
                'daily_stock' => (bool) $item->daily_stock,
                'is_active' => (bool) $item->is_active,
                'price' => $this->pricingService->currentItemPrice($item->id, $storeId),
                'sold_at' => $this->soldAt($item),
            ];

            $fields = array_intersect_key($data, array_flip(['name', 'unit', 'tracks_stock', 'daily_stock', 'is_active']));
            if (! empty($fields['daily_stock'])) {
                $fields['tracks_stock'] = true;
            }
            if (isset($data['category'])) {
                $fields['sell_category'] = trim($data['category']);
                $fields['is_drink'] = strcasecmp($fields['sell_category'], 'Drinks') === 0;
            }
            $item->update($fields);

            if ($useDefault) {
                DrinkPrice::where('item_id', $item->id)->where('store_id', $storeId)->where('is_active', true)
                    ->update(['is_active' => false]);
            } elseif (isset($data['price'])) {
                $this->setPrice($item, (float) $data['price'], $storeId);
            }

            if (array_key_exists('branches', $data)) {
                $this->setBranches($item, $data['branches']);
            }

            $item->refresh();
            $after = [
                'name' => $item->name,
                'unit' => $item->unit,
                'category' => $item->sell_category,
                'tracks_stock' => (bool) $item->tracks_stock,
                'daily_stock' => (bool) $item->daily_stock,
                'is_active' => (bool) $item->is_active,
                'price' => $this->pricingService->currentItemPrice($item->id, $storeId),
                'sold_at' => $this->soldAt($item),
            ];

            $changes = EditLog::diff($before, $after);
            if ($changes) {
                $where = $storeId ? ' at '.Store::find($storeId)->name : '';
                EditLog::record(
                    $request->user(), 'menu_item', $item->id, $item->name.$where,
                    isset($changes['price']) && count($changes) === 1 ? ($useDefault ? 'price_reset' : 'price_changed') : 'edited',
                    $changes, $data['reason'], $storeId,
                );
            }
        });

        return response()->json($this->row($item->fresh(), $storeId));
    }

    /** "Kira, Town" or "All branches", for the change log. */
    private function soldAt(Item $item): string
    {
        $off = ItemStoreSetting::where('item_id', $item->id)->where('on_menu', false)->pluck('store_id');
        if ($off->isEmpty()) {
            return 'All branches';
        }

        return Store::whereNotIn('id', $off)->orderBy('name')->pluck('name')->join(', ') ?: 'No branch';
    }

    private function setPrice(Item $item, float $price, ?int $storeId): void
    {
        DrinkPrice::where('item_id', $item->id)->where('store_id', $storeId)->where('is_active', true)
            ->update(['is_active' => false]);

        DrinkPrice::create([
            'item_id' => $item->id,
            'store_id' => $storeId,
            'price' => $price,
            'effective_from' => now()->toDateString(),
            'is_active' => true,
        ]);
    }

    private function row(Item $item, ?int $storeId): array
    {
        return [
            'item' => $item,
            'category' => $item->sell_category,
            'price' => $this->pricingService->currentItemPrice($item->id, $storeId),
            'tracks_stock' => (bool) $item->tracks_stock,
        ];
    }
}
