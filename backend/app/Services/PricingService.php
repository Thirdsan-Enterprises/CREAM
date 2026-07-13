<?php

namespace App\Services;

use App\Models\DrinkPrice;
use App\Models\PlatePrice;

class PricingService
{
    public function currentPlatePrice(?int $storeId): float
    {
        if ($storeId !== null) {
            $override = PlatePrice::where('store_id', $storeId)
                ->where('is_active', true)
                ->whereDate('effective_from', '<=', now()->toDateString())
                ->orderByDesc('effective_from')
                ->first();

            if ($override) {
                return (float) $override->price;
            }
        }

        $global = PlatePrice::whereNull('store_id')
            ->where('is_active', true)
            ->whereDate('effective_from', '<=', now()->toDateString())
            ->orderByDesc('effective_from')
            ->first();

        return (float) ($global->price ?? 25000);
    }

    public function currentDrinkPrice(int $itemId, ?int $storeId): ?float
    {
        if ($storeId !== null) {
            $override = DrinkPrice::where('item_id', $itemId)
                ->where('store_id', $storeId)
                ->where('is_active', true)
                ->whereDate('effective_from', '<=', now()->toDateString())
                ->orderByDesc('effective_from')
                ->first();

            if ($override) {
                return (float) $override->price;
            }
        }

        $global = DrinkPrice::where('item_id', $itemId)
            ->whereNull('store_id')
            ->where('is_active', true)
            ->whereDate('effective_from', '<=', now()->toDateString())
            ->orderByDesc('effective_from')
            ->first();

        return $global ? (float) $global->price : null;
    }
}
