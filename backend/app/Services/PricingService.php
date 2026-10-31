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

    /** Same as currentItemPrice; kept for callers written when only drinks were sold. */
    public function currentDrinkPrice(int $itemId, ?int $storeId): ?float
    {
        return $this->currentItemPrice($itemId, $storeId);
    }

    /**
     * The price of any menu item (drink, egg, tea...) at a branch: the
     * branch's own price if it has one, otherwise the price for all branches.
     * Prices live in drink_prices for historical reasons.
     */
    public function currentItemPrice(int $itemId, ?int $storeId): ?float
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
