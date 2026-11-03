<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

/**
 * As agreed with Cream (November 2026):
 * - the silver plate is a packing charge added when food is taken away,
 *   not a dish: it moves to the "Packing" heading;
 * - breakfast is sold at Town only, and breakfast made ahead (chapatis,
 *   mandazi...) is counted each morning like lunch plates.
 */
return new class extends Migration
{
    private const MADE_TO_ORDER = ['Milk Tea', 'Black Tea', 'Rolex', 'Omelette'];

    public function up(): void
    {
        DB::table('items')->where('is_sellable', true)->where('name', 'Silver plate')
            ->update(['sell_category' => 'Packing', 'tracks_stock' => false, 'daily_stock' => false]);

        $breakfast = DB::table('items')->where('is_sellable', true)->where('sell_category', 'Breakfast');
        (clone $breakfast)->whereNotIn('name', self::MADE_TO_ORDER)
            ->update(['tracks_stock' => true, 'daily_stock' => true]);

        $town = DB::table('stores')->whereRaw('UPPER(code) = ?', ['TOWN'])->value('id');
        if ($town) {
            DB::table('item_store_settings')
                ->whereIn('item_id', (clone $breakfast)->pluck('id'))
                ->where('store_id', '!=', $town)
                ->update(['on_menu' => false]);
        }
    }

    public function down(): void
    {
        DB::table('items')->where('is_sellable', true)->where('name', 'Silver plate')
            ->update(['sell_category' => 'Takeaway']);
    }
};
