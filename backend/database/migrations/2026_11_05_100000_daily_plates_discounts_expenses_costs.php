<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * - Daily plates: dishes counted per day ("40 Beef prepared"); each sale
 *   takes one off and the count starts again the next day.
 * - Purchases carry the price paid and the supplier (procurement ledger).
 * - A sale may carry a discount with a note.
 * - Branch expenses (transport, small purchases) paid from takings, by
 *   people the owner allows.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('items', function (Blueprint $table) {
            $table->boolean('daily_stock')->default(false)->after('tracks_stock');
        });

        Schema::table('stock_movements', function (Blueprint $table) {
            $table->enum('type', ['purchase', 'transfer_out', 'transfer_in', 'consumption', 'adjustment', 'prepared'])->change();
            $table->decimal('unit_cost', 12, 2)->nullable()->after('qty');
            $table->string('supplier')->nullable()->after('unit_cost');
        });

        Schema::table('sales', function (Blueprint $table) {
            $table->decimal('discount', 12, 2)->default(0)->after('total');
            $table->string('discount_note', 255)->nullable()->after('discount');
        });

        Schema::table('users', function (Blueprint $table) {
            $table->boolean('can_record_expenses')->default(false)->after('role');
        });

        Schema::create('expenses', function (Blueprint $table) {
            $table->id();
            $table->foreignId('store_id')->constrained('stores');
            $table->decimal('amount', 12, 2);
            $table->string('category', 50);
            $table->string('note', 255)->nullable();
            $table->enum('paid_from', ['cash', 'momo', 'airtel'])->default('cash');
            $table->foreignId('recorded_by')->constrained('users');
            $table->timestamp('spent_at');
            $table->timestamp('voided_at')->nullable();
            $table->foreignId('voided_by')->nullable()->constrained('users');
            $table->string('void_reason', 500)->nullable();
            $table->timestamps();
            $table->index(['store_id', 'spent_at']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('expenses');
        Schema::table('users', fn (Blueprint $t) => $t->dropColumn('can_record_expenses'));
        Schema::table('sales', fn (Blueprint $t) => $t->dropColumn(['discount', 'discount_note']));
        Schema::table('stock_movements', function (Blueprint $table) {
            $table->dropColumn(['unit_cost', 'supplier']);
            $table->enum('type', ['purchase', 'transfer_out', 'transfer_in', 'consumption', 'adjustment'])->change();
        });
        Schema::table('items', fn (Blueprint $t) => $t->dropColumn('daily_stock'));
    }
};
