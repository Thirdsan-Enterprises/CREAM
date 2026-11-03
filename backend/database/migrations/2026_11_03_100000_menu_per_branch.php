<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Each branch has its own menu: Town and Kira share one lunch menu priced
 * by the sauce, Lugogo has its own. A menu item is sold at a branch unless
 * that branch's row says otherwise.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('item_store_settings', function (Blueprint $table) {
            $table->boolean('on_menu')->default(true)->after('safety_stock');
        });
    }

    public function down(): void
    {
        Schema::table('item_store_settings', function (Blueprint $table) {
            $table->dropColumn('on_menu');
        });
    }
};
