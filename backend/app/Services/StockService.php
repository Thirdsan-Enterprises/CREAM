<?php

namespace App\Services;

use App\Models\Item;
use App\Models\ItemStoreSetting;
use App\Models\StockMovement;

class StockService
{
    public function balance(int $itemId, int $storeId): float
    {
        return (float) StockMovement::query()
            ->where('item_id', $itemId)
            ->where('store_id', $storeId)
            ->sum('qty');
    }

    public function balances(int $itemId): array
    {
        $item = Item::with('storeSettings.store')->findOrFail($itemId);

        $sums = StockMovement::query()
            ->where('item_id', $itemId)
            ->selectRaw('store_id, SUM(qty) as balance')
            ->groupBy('store_id')
            ->pluck('balance', 'store_id');

        return $item->storeSettings->map(function ($setting) use ($sums) {
            $balance = (float) ($sums[$setting->store_id] ?? 0);

            return [
                'store_id' => $setting->store_id,
                'store_name' => $setting->store->name,
                'balance' => $balance,
                'safety_stock' => (float) $setting->safety_stock,
                'status' => $balance <= (float) $setting->safety_stock ? 'Re-Order' : 'Stock Sufficient',
            ];
        })->values()->all();
    }

    public function storeItemStatuses(int $storeId): array
    {
        $settings = ItemStoreSetting::query()->where('store_id', $storeId)->with('item')->get();

        $balances = StockMovement::query()
            ->where('store_id', $storeId)
            ->selectRaw('item_id, SUM(qty) as balance')
            ->groupBy('item_id')
            ->pluck('balance', 'item_id');

        return $settings->map(function ($setting) use ($balances) {
            $balance = (float) ($balances[$setting->item_id] ?? 0);

            return [
                'item_id' => $setting->item_id,
                'item_name' => $setting->item->name,
                'balance' => $balance,
                'safety_stock' => (float) $setting->safety_stock,
                'status' => $balance <= (float) $setting->safety_stock ? 'Re-Order' : 'Stock Sufficient',
            ];
        })->values()->all();
    }
}
