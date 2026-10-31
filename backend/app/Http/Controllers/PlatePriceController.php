<?php

namespace App\Http\Controllers;

use App\Models\EditLog;
use App\Models\PlatePrice;
use App\Models\Store;
use App\Services\PricingService;
use App\Support\StoreScope;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\ValidationException;

class PlatePriceController extends Controller
{
    public function __construct(private readonly PricingService $pricingService) {}

    public function show(Request $request)
    {
        $storeId = StoreScope::resolve($request->user(), $request->integer('store_id') ?: null);

        return response()->json([
            'store_id' => $storeId,
            'price' => $this->pricingService->currentPlatePrice($storeId),
        ]);
    }

    /**
     * Set the plate price for every branch (no store_id) or give one branch
     * its own price, e.g. Town at 15,000. "use_default" removes a branch's
     * own price so it goes back to the price for all branches. Every change
     * is logged with its reason.
     */
    public function update(Request $request)
    {
        $data = $request->validate([
            'store_id' => ['nullable', 'exists:stores,id'],
            'use_default' => ['sometimes', 'boolean'],
            'price' => ['required_unless:use_default,true', 'nullable', 'numeric', 'gt:0'],
            'effective_from' => ['nullable', 'date'],
            'reason' => ['required', 'string', 'max:500'],
        ], [
            'reason.required' => 'Say why the price is changing.',
        ]);

        $storeId = $data['store_id'] ?? null;
        $useDefault = (bool) ($data['use_default'] ?? false);
        if ($useDefault && $storeId === null) {
            throw ValidationException::withMessages(['store_id' => ['Choose the branch to put back on the price for all branches.']]);
        }

        $before = $this->pricingService->currentPlatePrice($storeId);
        $label = $storeId ? 'Plate price at '.Store::find($storeId)->name : 'Plate price for all branches';

        $price = DB::transaction(function () use ($data, $storeId, $useDefault, $before, $label, $request) {
            PlatePrice::where('store_id', $storeId)->where('is_active', true)->update(['is_active' => false]);

            $price = $useDefault ? null : PlatePrice::create([
                'store_id' => $storeId,
                'price' => $data['price'],
                'effective_from' => $data['effective_from'] ?? now()->toDateString(),
                'is_active' => true,
            ]);

            EditLog::record(
                $request->user(),
                'plate_price',
                $storeId,
                $label,
                $useDefault ? 'price_reset' : 'price_changed',
                ['price' => ['from' => $before, 'to' => $this->pricingService->currentPlatePrice($storeId)]],
                $data['reason'],
                $storeId,
            );

            return $price;
        });

        return response()->json([
            'store_id' => $storeId,
            'price' => $this->pricingService->currentPlatePrice($storeId),
            'own_price' => $price !== null && $storeId !== null,
        ], 201);
    }
}
