<?php

namespace App\Http\Controllers;

use Illuminate\Http\Request;

abstract class Controller
{
    /**
     * Page size for a list endpoint. The app shows each list in one go, so
     * the default must cover a whole catalogue: at Laravel's default of 15
     * only 15 items, users or customers were ever reachable. Callers can
     * ask for fewer or more with ?per_page=, capped so one request stays
     * reasonable.
     */
    protected function perPage(Request $request, int $default = 100): int
    {
        $requested = $request->integer('per_page');

        return $requested > 0 ? min($requested, 500) : $default;
    }
}
