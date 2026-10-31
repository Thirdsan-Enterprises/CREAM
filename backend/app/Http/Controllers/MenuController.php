<?php

namespace App\Http\Controllers;

use App\Models\DrinkPrice;
use App\Models\Item;
use App\Models\ItemStoreSetting;
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
            ->orderBy('sell_category')
            ->orderBy('name')
            ->get();

        return $items->map(fn (Item $item) => [
            'item' => $item,
            'category' => $item->sell_category ?? ($item->is_drink ? 'Drinks' : 'Other'),
            'price' => $this->pricingService->currentItemPrice($item->id, $storeId),
            'tracks_stock' => (bool) $item->tracks_stock,
            'balance' => $storeId && $item->tracks_stock
                ? $this->stockService->balance($item->id, $storeId)
                : null,
        ])->values();
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
            'safety_stock' => ['nullable', 'numeric', 'min:0'],
        ]);

        $item = DB::transaction(function () use ($data) {
            $category = trim($data['category']);
            $attributes = [
                'is_sellable' => true,
                'sell_category' => $category,
                'tracks_stock' => $data['tracks_stock'] ?? true,
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
            $this->setPrice($item, (float) $data['price'], $data['store_id'] ?? null);

            return $item;
        });

        return response()->json($this->row($item, $data['store_id'] ?? null), 201);
    }

    /** Change a menu item's details, or its price for all branches or one. */
    public function update(Request $request, Item $item)
    {
        $data = $request->validate([
            'name' => ['sometimes', 'string', 'max:255'],
            'unit' => ['sometimes', 'string', 'max:50'],
            'category' => ['sometimes', 'string', 'max:50'],
            'tracks_stock' => ['sometimes', 'boolean'],
            'is_active' => ['sometimes', 'boolean'],
            'price' => ['sometimes', 'numeric', 'gt:0'],
            'store_id' => ['nullable', 'exists:stores,id'],
        ]);

        DB::transaction(function () use ($item, $data) {
            $fields = array_intersect_key($data, array_flip(['name', 'unit', 'tracks_stock', 'is_active']));
            if (isset($data['category'])) {
                $fields['sell_category'] = trim($data['category']);
                $fields['is_drink'] = strcasecmp($fields['sell_category'], 'Drinks') === 0;
            }
            $item->update($fields);

            if (isset($data['price'])) {
                $this->setPrice($item, (float) $data['price'], $data['store_id'] ?? null);
            }
        });

        return response()->json($this->row($item->fresh(), $data['store_id'] ?? null));
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
