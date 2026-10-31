<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * A sale entered by mistake is voided, never deleted: it stays in the
 * record, marked with who voided it, when and why, and leaves the totals.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('sales', function (Blueprint $table) {
            $table->timestamp('voided_at')->nullable()->after('sold_at');
            $table->foreignId('voided_by')->nullable()->after('voided_at')->constrained('users');
            $table->text('void_reason')->nullable()->after('voided_by');
            $table->index(['store_id', 'voided_at']);
        });
    }

    public function down(): void
    {
        Schema::table('sales', function (Blueprint $table) {
            $table->dropIndex(['store_id', 'voided_at']);
            $table->dropConstrainedForeignId('voided_by');
            $table->dropColumn(['voided_at', 'void_reason']);
        });
    }
};
