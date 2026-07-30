<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Adds 'lpo' as a third customer account type (alongside prepaid/credit,
     * same balance mechanics — floor at zero, funded by topping up instead
     * of paying cash) and as a payment method for one-off sales not tied to
     * a running account.
     */
    public function up(): void
    {
        Schema::table('customers', function (Blueprint $table) {
            $table->enum('account_type', ['prepaid', 'credit', 'lpo'])->change();
        });

        Schema::table('sales', function (Blueprint $table) {
            $table->enum('payment_method', ['cash', 'momo', 'airtel', 'account', 'lpo'])->change();
        });
    }

    public function down(): void
    {
        Schema::table('customers', function (Blueprint $table) {
            $table->enum('account_type', ['prepaid', 'credit'])->change();
        });

        Schema::table('sales', function (Blueprint $table) {
            $table->enum('payment_method', ['cash', 'momo', 'airtel', 'account'])->change();
        });
    }
};
