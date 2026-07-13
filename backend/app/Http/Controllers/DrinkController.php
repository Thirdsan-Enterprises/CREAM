<?php

namespace App\Http\Controllers;

use App\Models\DrinkPrice;
use App\Models\Item;
use App\Services\PricingService;
use App\Support\StoreScope;
use Illuminate\Http\Request;

class DrinkController extends Controller
{
    public function __construct(private readonly PricingService $pricingService) {}

    public function index(Request $request)
    {
        $storeId = StoreScope::resolve($request->user(), $request->integer('store_id') ?: null);

        $drinks = Item::query()->where('is_drink', true)->where('is_active', true)->orderBy('name')->get();

        return $drinks->map(fn (Item $item) => [
            'item' => $item,
            'price' => $this->pricingService->currentDrinkPrice($item->id, $storeId),
        ])->values();
    }

    public function store(Request $request)
    {
        $data = $request->validate([
            'name' => ['required', 'string', 'max:255'],
            'unit' => ['required', 'string', 'max:50'],
            'price' => ['required', 'numeric', 'gt:0'],
            'store_id' => ['nullable', 'exists:stores,id'],
            'effective_from' => ['nullable', 'date'],
        ]);

        $item = Item::create([
            'name' => $data['name'],
            'unit' => $data['unit'],
            'is_drink' => true,
            'is_active' => true,
        ]);

        $price = DrinkPrice::create([
            'item_id' => $item->id,
            'store_id' => $data['store_id'] ?? null,
            'price' => $data['price'],
            'effective_from' => $data['effective_from'] ?? now()->toDateString(),
            'is_active' => true,
        ]);

        return response()->json(['item' => $item, 'price' => $price], 201);
    }

    public function update(Request $request, Item $item)
    {
        $data = $request->validate([
            'name' => ['sometimes', 'string', 'max:255'],
            'unit' => ['sometimes', 'string', 'max:50'],
            'is_active' => ['sometimes', 'boolean'],
            'price' => ['sometimes', 'numeric', 'gt:0'],
            'store_id' => ['nullable', 'exists:stores,id'],
            'effective_from' => ['nullable', 'date'],
        ]);

        $item->update(array_intersect_key($data, array_flip(['name', 'unit', 'is_active'])));

        if (isset($data['price'])) {
            $storeId = $data['store_id'] ?? null;

            DrinkPrice::where('item_id', $item->id)->where('store_id', $storeId)->where('is_active', true)
                ->update(['is_active' => false]);

            DrinkPrice::create([
                'item_id' => $item->id,
                'store_id' => $storeId,
                'price' => $data['price'],
                'effective_from' => $data['effective_from'] ?? now()->toDateString(),
                'is_active' => true,
            ]);
        }

        return response()->json([
            'item' => $item,
            'price' => $this->pricingService->currentDrinkPrice($item->id, $data['store_id'] ?? null),
        ]);
    }
}
