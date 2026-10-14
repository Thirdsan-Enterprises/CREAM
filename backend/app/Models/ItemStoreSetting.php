<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

#[Fillable(['item_id', 'store_id', 'safety_stock'])]
class ItemStoreSetting extends Model
{
    /**
     * Give a (new) item a stock row at every branch. Stock lists, transfers
     * and Re-Order status all start from these rows, so an item without
     * them can be bought but never seen, dispatched or sold. Existing
     * rows are left alone, so this is safe to call again.
     */
    public static function backfillForItem(Item $item, float $safetyStock = 0): void
    {
        foreach (Store::query()->pluck('id') as $storeId) {
            static::firstOrCreate(
                ['item_id' => $item->id, 'store_id' => $storeId],
                ['safety_stock' => $safetyStock],
            );
        }
    }

    /** Give a (new) branch a stock row for every item, at level 0. */
    public static function backfillForStore(Store $store): void
    {
        foreach (Item::query()->pluck('id') as $itemId) {
            static::firstOrCreate(
                ['item_id' => $itemId, 'store_id' => $store->id],
                ['safety_stock' => 0],
            );
        }
    }

    public function item(): BelongsTo
    {
        return $this->belongsTo(Item::class);
    }

    public function store(): BelongsTo
    {
        return $this->belongsTo(Store::class);
    }
}
