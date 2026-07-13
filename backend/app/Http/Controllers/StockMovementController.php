<?php

namespace App\Http\Controllers;

use App\Models\StockMovement;
use App\Models\Store;
use App\Services\StockService;
use App\Support\StoreScope;
use Illuminate\Http\Request;
use Illuminate\Validation\ValidationException;

class StockMovementController extends Controller
{
    public function __construct(private readonly StockService $stockService) {}

    public function status(Request $request)
    {
        $storeId = StoreScope::resolveRequired($request->user(), $request->integer('store_id') ?: null);
        StoreScope::assertAccess($request->user(), $storeId);

        return response()->json([
            'store_id' => $storeId,
            'items' => $this->stockService->storeItemStatuses($storeId),
        ]);
    }

    public function index(Request $request)
    {
        $user = $request->user();

        $query = StockMovement::query()->with(['item', 'store', 'user'])->orderByDesc('occurred_at');

        $storeId = StoreScope::resolve($user, $request->integer('store_id') ?: null);
        if ($storeId !== null) {
            $query->where('store_id', $storeId);
        }

        if ($request->filled('item_id')) {
            $query->where('item_id', $request->integer('item_id'));
        }

        if ($request->filled('type')) {
            $query->where('type', $request->string('type'));
        }

        if ($request->filled('from')) {
            $query->where('occurred_at', '>=', $request->date('from'));
        }

        if ($request->filled('to')) {
            $query->where('occurred_at', '<=', $request->date('to')->endOfDay());
        }

        return $query->paginate();
    }

    public function purchase(Request $request)
    {
        $user = $request->user();

        $data = $request->validate([
            'store_id' => ['nullable', 'exists:stores,id'],
            'item_id' => ['required', 'exists:items,id'],
            'qty' => ['required', 'numeric', 'gt:0'],
            'note' => ['nullable', 'string'],
            'occurred_at' => ['nullable', 'date'],
        ]);

        $storeId = StoreScope::resolveRequired($user, $data['store_id'] ?? null);
        StoreScope::assertAccess($user, $storeId);

        $store = Store::findOrFail($storeId);
        if (! $store->is_main) {
            throw ValidationException::withMessages([
                'store_id' => ['Purchases (Stock In) can only be recorded at the main store.'],
            ]);
        }

        $movement = StockMovement::create([
            'item_id' => $data['item_id'],
            'store_id' => $storeId,
            'type' => StockMovement::TYPE_PURCHASE,
            'qty' => $data['qty'],
            'note' => $data['note'] ?? null,
            'user_id' => $user->id,
            'occurred_at' => $data['occurred_at'] ?? now(),
        ]);

        return response()->json($movement, 201);
    }

    public function consumption(Request $request)
    {
        $user = $request->user();

        $data = $request->validate([
            'store_id' => ['nullable', 'exists:stores,id'],
            'item_id' => ['required', 'exists:items,id'],
            'qty' => ['required', 'numeric', 'gt:0'],
            'note' => ['nullable', 'string'],
            'occurred_at' => ['nullable', 'date'],
        ]);

        $storeId = StoreScope::resolveRequired($user, $data['store_id'] ?? null);
        StoreScope::assertAccess($user, $storeId);

        $movement = StockMovement::create([
            'item_id' => $data['item_id'],
            'store_id' => $storeId,
            'type' => StockMovement::TYPE_CONSUMPTION,
            'qty' => -abs($data['qty']),
            'note' => $data['note'] ?? null,
            'user_id' => $user->id,
            'occurred_at' => $data['occurred_at'] ?? now(),
        ]);

        return response()->json($movement, 201);
    }

    public function adjustment(Request $request)
    {
        $user = $request->user();

        $data = $request->validate([
            'store_id' => ['nullable', 'exists:stores,id'],
            'item_id' => ['required', 'exists:items,id'],
            'qty' => ['required', 'numeric', 'not_in:0'],
            'note' => ['required', 'string'],
            'occurred_at' => ['nullable', 'date'],
        ]);

        $storeId = StoreScope::resolveRequired($user, $data['store_id'] ?? null);
        StoreScope::assertAccess($user, $storeId);

        $movement = StockMovement::create([
            'item_id' => $data['item_id'],
            'store_id' => $storeId,
            'type' => StockMovement::TYPE_ADJUSTMENT,
            'qty' => $data['qty'],
            'note' => $data['note'],
            'user_id' => $user->id,
            'occurred_at' => $data['occurred_at'] ?? now(),
        ]);

        return response()->json($movement, 201);
    }
}
