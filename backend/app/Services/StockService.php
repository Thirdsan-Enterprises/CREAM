<?php

namespace App\Services;

use App\Models\Item;
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
}
