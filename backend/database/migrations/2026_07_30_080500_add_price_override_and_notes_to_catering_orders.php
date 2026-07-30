<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('catering_orders', function (Blueprint $table) {
            // Snapshot of the per-plate price actually charged for this order —
            // defaults to the selected package's price, but can be overridden
            // at order-creation time for negotiated/custom pricing.
            $table->decimal('price_per_plate', 12, 2)->nullable()->after('catering_package_id');
            $table->text('notes')->nullable()->after('number_of_plates');
        });
    }

    public function down(): void
    {
        Schema::table('catering_orders', function (Blueprint $table) {
            $table->dropColumn(['price_per_plate', 'notes']);
        });
    }
};
