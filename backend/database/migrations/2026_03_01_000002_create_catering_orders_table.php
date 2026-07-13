<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('catering_orders', function (Blueprint $table) {
            $table->id();
            $table->string('client_name');
            $table->string('client_phone');
            $table->string('event_name')->nullable();
            $table->date('event_date');
            $table->foreignId('catering_package_id')->constrained('catering_packages');
            $table->unsignedInteger('number_of_plates');
            $table->decimal('total_amount', 12, 2);
            $table->enum('status', ['quoted', 'confirmed', 'delivered', 'settled', 'cancelled'])->default('quoted');
            $table->foreignId('created_by')->constrained('users');
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('catering_orders');
    }
};
