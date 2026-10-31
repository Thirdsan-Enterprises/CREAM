<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Anything can be sold on its own, not just plates and drinks: an egg, a cup
 * of tea, a chapati at breakfast. An item is on the menu when is_sellable is
 * set; sell_category groups it on the Sell screen (Drinks, Breakfast...);
 * tracks_stock says whether selling it takes it off the branch's stock (an
 * egg does; a cup of tea, made from other stock, does not).
 *
 * Existing drinks become menu items in the Drinks category, tracking stock as
 * before. Prices for every menu item stay in drink_prices.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('items', function (Blueprint $table) {
            $table->boolean('is_sellable')->default(false)->after('is_drink');
            $table->string('sell_category', 50)->nullable()->after('is_sellable');
            $table->boolean('tracks_stock')->default(true)->after('sell_category');
        });

        DB::table('items')->where('is_drink', true)->update([
            'is_sellable' => true,
            'sell_category' => 'Drinks',
            'tracks_stock' => true,
        ]);

        Schema::table('sale_items', function (Blueprint $table) {
            $table->enum('item_type', ['plate', 'drink', 'item'])->change();
        });
    }

    public function down(): void
    {
        DB::table('sale_items')->where('item_type', 'item')->delete();

        Schema::table('sale_items', function (Blueprint $table) {
            $table->enum('item_type', ['plate', 'drink'])->change();
        });

        Schema::table('items', function (Blueprint $table) {
            $table->dropColumn(['is_sellable', 'sell_category', 'tracks_stock']);
        });
    }
};
