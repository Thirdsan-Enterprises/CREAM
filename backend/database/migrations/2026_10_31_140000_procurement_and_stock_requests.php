<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * The procurement unit (the main store) buys for everyone and sends stock to
 * the branches. It may be a branch that also sells (Kira today) or a unit of
 * its own that does not ("sells" false). Branches ask it for what they are
 * missing through stock requests.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('stores', function (Blueprint $table) {
            $table->boolean('sells')->default(true)->after('is_main');
        });

        Schema::create('stock_requests', function (Blueprint $table) {
            $table->id();
            $table->foreignId('store_id')->constrained('stores');
            $table->foreignId('requested_by')->constrained('users');
            // open → sent (as a transfer) | declined | cancelled
            $table->enum('status', ['open', 'sent', 'declined', 'cancelled'])->default('open');
            $table->text('note')->nullable();
            $table->foreignId('responded_by')->nullable()->constrained('users');
            $table->timestamp('responded_at')->nullable();
            $table->text('response_note')->nullable();
            $table->foreignId('stock_transfer_id')->nullable()->constrained('stock_transfers');
            $table->timestamps();

            $table->index(['status', 'created_at']);
        });

        Schema::create('stock_request_items', function (Blueprint $table) {
            $table->id();
            $table->foreignId('stock_request_id')->constrained('stock_requests')->cascadeOnDelete();
            $table->foreignId('item_id')->constrained('items');
            $table->decimal('qty_requested', 12, 2);
            $table->decimal('qty_sent', 12, 2)->nullable();
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('stock_request_items');
        Schema::dropIfExists('stock_requests');
        Schema::table('stores', function (Blueprint $table) {
            $table->dropColumn('sells');
        });
    }
};
