<?php

namespace App\Providers;

use Illuminate\Support\Facades\Schema;
use Illuminate\Support\ServiceProvider;

class AppServiceProvider extends ServiceProvider
{
    /**
     * Register any application services.
     */
    public function register(): void
    {
        //
    }

    /**
     * Bootstrap any application services.
     */
    public function boot(): void
    {
        // Keeps unique/indexed varchar columns under the 1000-byte key
        // length limit on hosts running MyISAM or an older InnoDB row
        // format with utf8mb4 (191 chars * 4 bytes = 764 bytes).
        Schema::defaultStringLength(191);
    }
}
