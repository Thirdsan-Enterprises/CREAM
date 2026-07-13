<?php

namespace App\Http\Controllers;

use App\Models\PlatePrice;
use App\Services\PricingService;
use App\Support\StoreScope;
use Illuminate\Http\Request;

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

    public function update(Request $request)
    {
        $data = $request->validate([
            'store_id' => ['nullable', 'exists:stores,id'],
            'price' => ['required', 'numeric', 'gt:0'],
            'effective_from' => ['nullable', 'date'],
        ]);

        $storeId = $data['store_id'] ?? null;

        PlatePrice::where('store_id', $storeId)->where('is_active', true)->update(['is_active' => false]);

        $price = PlatePrice::create([
            'store_id' => $storeId,
            'price' => $data['price'],
            'effective_from' => $data['effective_from'] ?? now()->toDateString(),
            'is_active' => true,
        ]);

        return response()->json($price, 201);
    }
}
