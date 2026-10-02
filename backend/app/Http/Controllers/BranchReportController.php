<?php

namespace App\Http\Controllers;

use App\Models\Store;
use App\Services\BranchPerformanceService;
use App\Support\StoreScope;
use Illuminate\Http\Request;

/**
 * Owner-facing branch performance: how much each outlet is taking, what
 * it's selling, who is selling it, and how its stock is holding up.
 * Daily outlet sales only — catering stays in its own report.
 */
class BranchReportController extends Controller
{
    public function __construct(private readonly BranchPerformanceService $service) {}

    /** All branches side by side (admin). */
    public function index(Request $request)
    {
        return response()->json($this->service->overview($this->period($request)));
    }

    /** One branch in depth (admin, or that branch's own manager). */
    public function show(Request $request, Store $store)
    {
        StoreScope::assertAccess($request->user(), $store->id);

        return response()->json($this->service->branch($store, $this->period($request)));
    }

    private function period(Request $request): array
    {
        $data = $request->validate([
            'from' => ['nullable', 'date_format:Y-m-d'],
            'to' => ['nullable', 'date_format:Y-m-d', 'after_or_equal:from'],
        ]);

        $period = $this->service->period($data['from'] ?? null, $data['to'] ?? null);

        if ($period['days'] > 366) {
            abort(422, 'Choose a period of one year or less.');
        }

        return $period;
    }
}
