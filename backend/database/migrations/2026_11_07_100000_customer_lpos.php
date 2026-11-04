<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * An LPO (local purchase order) from a company whose staff eat at Cream:
 * its number, its value, how many lunch plates it pays for and what it
 * covers (lunch, breakfast, drinks). Its value goes onto the customer's
 * account; each sale charged to it records which LPO it was charged to.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('customer_lpos', function (Blueprint $table) {
            $table->id();
            $table->foreignId('customer_id')->constrained('customers');
            $table->string('number', 100)->nullable();
            $table->decimal('amount', 12, 2);
            // Lunch plates it pays for; null = no plate limit, only the amount.
            $table->unsignedInteger('plates')->nullable();
            // Headings it covers, e.g. ["Lunch", "Breakfast"].
            $table->json('covers');
            $table->string('note', 255)->nullable();
            $table->foreignId('created_by')->constrained('users');
            $table->timestamps();
            $table->index(['customer_id', 'id']);
        });

        Schema::table('sales', function (Blueprint $table) {
            $table->foreignId('customer_lpo_id')->nullable()->after('customer_id')->constrained('customer_lpos');
        });
    }

    public function down(): void
    {
        Schema::table('sales', function (Blueprint $table) {
            $table->dropConstrainedForeignId('customer_lpo_id');
        });
        Schema::dropIfExists('customer_lpos');
    }
};
