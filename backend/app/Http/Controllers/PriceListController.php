<?php

namespace App\Http\Controllers;

use App\Models\DrinkPrice;
use App\Models\Item;
use App\Models\PlatePrice;
use App\Models\Store;
use App\Services\PricingService;

/**
 * Every price in one place for the owner: the plate and each menu item,
 * the price for all branches, and which branches charge their own.
 */
class PriceListController extends Controller
{
    public function __construct(private readonly PricingService $pricingService) {}

    public function index()
    {
        $stores = Store::where('is_active', true)->orderByDesc('is_main')->orderBy('name')->get(['id', 'name']);

        $plateOwn = PlatePrice::whereNotNull('store_id')->where('is_active', true)->pluck('store_id')->flip();
        $plate = [
            'default' => $this->pricingService->currentPlatePrice(null),
            'branches' => $stores->map(fn (Store $store) => [
                'store_id' => $store->id,
                'store_name' => $store->name,
                'price' => $this->pricingService->currentPlatePrice($store->id),
                'own' => $plateOwn->has($store->id),
            ])->values(),
        ];

        $items = Item::query()
            ->where(fn ($q) => $q->where('is_sellable', true)->orWhere('is_drink', true))
            ->orderBy('sell_category')->orderBy('name')
            ->get();
        $itemOwn = DrinkPrice::whereNotNull('store_id')->where('is_active', true)
            ->get(['item_id', 'store_id'])
            ->groupBy('item_id')
            ->map(fn ($rows) => $rows->pluck('store_id')->flip());

        return response()->json([
            'stores' => $stores,
            'plate' => $plate,
            'items' => $items->map(fn (Item $item) => [
                'item' => $item,
                'category' => $item->sell_category ?? ($item->is_drink ? 'Drinks' : 'Other'),
                'tracks_stock' => (bool) $item->tracks_stock,
                'is_active' => (bool) $item->is_active,
                'default' => $this->pricingService->currentItemPrice($item->id, null),
                'branches' => $stores->map(fn (Store $store) => [
                    'store_id' => $store->id,
                    'store_name' => $store->name,
                    'price' => $this->pricingService->currentItemPrice($item->id, $store->id),
                    'own' => isset($itemOwn[$item->id]) && $itemOwn[$item->id]->has($store->id),
                ])->values(),
            ])->values(),
        ]);
    }
}
