<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('sales', function (Blueprint $table) {
            $table->id();
            $table->foreignId('store_id')->constrained();
            $table->foreignId('sold_by')->constrained('users');
            $table->enum('payment_method', ['cash', 'momo', 'airtel', 'account']);
            $table->foreignId('customer_id')->nullable()->constrained();
            $table->decimal('total', 12, 2)->default(0);
            $table->timestamp('sold_at');
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('sales');
    }
};
