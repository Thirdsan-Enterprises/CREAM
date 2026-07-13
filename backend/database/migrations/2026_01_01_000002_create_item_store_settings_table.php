<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('item_store_settings', function (Blueprint $table) {
            $table->id();
            $table->foreignId('item_id')->constrained()->cascadeOnDelete();
            $table->foreignId('store_id')->constrained()->cascadeOnDelete();
            $table->decimal('safety_stock', 12, 2)->default(0);
            $table->timestamps();

            $table->unique(['item_id', 'store_id']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('item_store_settings');
    }
};
