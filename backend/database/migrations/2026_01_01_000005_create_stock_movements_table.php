<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('stock_movements', function (Blueprint $table) {
            $table->id();
            $table->foreignId('item_id')->constrained();
            $table->foreignId('store_id')->constrained();
            $table->enum('type', ['purchase', 'transfer_out', 'transfer_in', 'consumption', 'adjustment']);
            $table->decimal('qty', 12, 2);
            $table->foreignId('related_transfer_id')->nullable()->constrained('stock_transfers');
            $table->string('note')->nullable();
            $table->foreignId('user_id')->constrained();
            $table->timestamp('occurred_at');
            $table->timestamps();

            $table->index(['item_id', 'store_id']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('stock_movements');
    }
};
