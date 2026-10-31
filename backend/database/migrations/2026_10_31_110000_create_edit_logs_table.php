<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * A record of every change made to something already entered: who changed
 * it, at which branch, what it was before and after, and the reason given.
 * Rows are only ever added, never edited or removed.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('edit_logs', function (Blueprint $table) {
            $table->id();
            $table->foreignId('user_id')->constrained('users');
            $table->foreignId('store_id')->nullable()->constrained('stores');
            // What was changed, e.g. "sale", "plate_price", "customer".
            $table->string('subject_type', 50);
            $table->unsignedBigInteger('subject_id')->nullable();
            // A short label people can read, e.g. "Sale #120" or "Plate price at Town".
            $table->string('subject_label');
            // e.g. "price_changed", "voided", "edited".
            $table->string('action', 50);
            // {field: {from: ..., to: ...}}
            $table->json('changes')->nullable();
            $table->text('reason');
            $table->timestamp('created_at')->useCurrent();

            $table->index(['subject_type', 'subject_id']);
            $table->index('created_at');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('edit_logs');
    }
};
