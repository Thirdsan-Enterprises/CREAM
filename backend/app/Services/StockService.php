<?php

namespace App\Services;

use App\Models\Item;
use App\Models\ItemStoreSetting;
use App\Models\StockMovement;
use Carbon\CarbonImmutable;

class StockService
{
    public function balance(int $itemId, int $storeId): float
    {
        $query = StockMovement::query()
            ->where('item_id', $itemId)
            ->where('store_id', $storeId);

        // A dish counted per day: only today's plates count; yesterday's
        // left-overs are not on sale today.
        if (Item::whereKey($itemId)->value('daily_stock')) {
            $query->where('occurred_at', '>=', self::startOfToday());
        }

        return (float) $query->sum('qty');
    }

    /** Midnight in the business's time zone, as UTC. */
    public static function startOfToday(): CarbonImmutable
    {
        return CarbonImmutable::now(config('app.business_timezone', 'Africa/Kampala'))->startOfDay()->utc();
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
        // Only what is counted on a shelf: kitchen stock and drinks, not
        // dishes made to order (lunch, tea).
        $settings = ItemStoreSetting::query()->where('store_id', $storeId)
            // Plates counted per day are handled under Today's plates.
            ->whereHas('item', fn ($q) => $q->where('tracks_stock', true)->where('daily_stock', false)->where('is_active', true))
            ->with('item')->get();

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
                'is_drink' => (bool) $setting->item->is_drink,
                'balance' => $balance,
                'safety_stock' => (float) $setting->safety_stock,
                'status' => $balance <= (float) $setting->safety_stock ? 'Re-Order' : 'Stock Sufficient',
            ];
        })->values()->all();
    }
}
