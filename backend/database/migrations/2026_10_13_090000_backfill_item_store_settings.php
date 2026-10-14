<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

/**
 * Items, drinks and branches added through the app before they were given
 * stock rows at creation never showed up in any stock list. Give every
 * item a row at every branch (level 0) wherever one is missing. Rows that
 * already exist, with their re-order levels, are untouched.
 */
return new class extends Migration
{
    public function up(): void
    {
        $existing = DB::table('item_store_settings')
            ->get(['item_id', 'store_id'])
            ->mapWithKeys(fn ($row) => [$row->item_id.'-'.$row->store_id => true]);

        $now = now();
        $missing = [];

        foreach (DB::table('items')->pluck('id') as $itemId) {
            foreach (DB::table('stores')->pluck('id') as $storeId) {
                if (! isset($existing[$itemId.'-'.$storeId])) {
                    $missing[] = [
                        'item_id' => $itemId, 'store_id' => $storeId, 'safety_stock' => 0,
                        'created_at' => $now, 'updated_at' => $now,
                    ];
                }
            }
        }

        foreach (array_chunk($missing, 200) as $chunk) {
            DB::table('item_store_settings')->insert($chunk);
        }
    }

    public function down(): void
    {
        // Nothing to undo: the rows are valid data, not a schema change.
    }
};
