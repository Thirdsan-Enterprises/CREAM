<?php

namespace App\Http\Controllers;

use App\Models\Item;
use App\Models\StockMovement;
use App\Models\Store;
use App\Services\StockService;
use App\Support\StoreScope;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\ValidationException;

/**
 * Today's plates: each morning a branch says how many plates of each dish
 * it prepared ("40 Beef"); every sale takes one off, and the count starts
 * again the next day.
 */
class DailyPlatesController extends Controller
{
    public function __construct(private readonly StockService $stockService) {}

    /** Prepared, sold and left today for each dish counted per day. */
    public function index(Request $request)
    {
        $storeId = StoreScope::resolveRequired($request->user(), $request->integer('store_id') ?: null);
        $since = StockService::startOfToday();

        $dishes = Item::query()
            ->where('is_active', true)->where('daily_stock', true)
            ->whereDoesntHave('storeSettings', fn ($q) => $q->where('store_id', $storeId)->where('on_menu', false))
            ->get()
            ->sortBy(fn (Item $i) => [MenuController::headingOrder($i), $i->name])
            ->values();

        $sums = StockMovement::query()
            ->where('store_id', $storeId)
            ->whereIn('item_id', $dishes->pluck('id'))
            ->where('occurred_at', '>=', $since)
            ->selectRaw('item_id, type, SUM(qty) as qty')
            ->groupBy('item_id', 'type')
            ->get()
            ->groupBy('item_id');

        return response()->json([
            'store_id' => $storeId,
            'dishes' => $dishes->map(function (Item $dish) use ($sums) {
                $rows = $sums[$dish->id] ?? collect();
                $prepared = (float) $rows->where('type', StockMovement::TYPE_PREPARED)->sum('qty');
                $sold = abs((float) $rows->where('type', StockMovement::TYPE_CONSUMPTION)->sum('qty'));

                return [
                    'item_id' => $dish->id,
                    'name' => $dish->name,
                    'category' => $dish->sell_category,
                    'prepared' => $prepared,
                    'sold' => $sold,
                    'left' => (float) $rows->sum('qty'),
                ];
            })->values(),
        ]);
    }

    /**
     * Add plates prepared today, e.g. 40 Beef. A negative number takes some
     * off (counted wrongly), never below what is left.
     */
    public function store(Request $request)
    {
        $user = $request->user();
        $data = $request->validate([
            'store_id' => ['nullable', 'exists:stores,id'],
            'items' => ['required', 'array', 'min:1'],
            'items.*.item_id' => ['required', 'distinct', 'exists:items,id'],
            'items.*.qty' => ['required', 'integer', 'not_in:0', 'min:-1000', 'max:5000'],
        ]);
        $storeId = StoreScope::resolveRequired($user, $data['store_id'] ?? null);
        StoreScope::assertAccess($user, $storeId);
        $branch = Store::findOrFail($storeId)->name;

        DB::transaction(function () use ($data, $storeId, $user, $branch) {
            foreach ($data['items'] as $line) {
                $dish = Item::findOrFail($line['item_id']);
                if (! $dish->daily_stock) {
                    throw ValidationException::withMessages(['items' => ["{$dish->name} is not counted per day."]]);
                }
                $left = $this->stockService->balance($dish->id, $storeId);
                if ($left + $line['qty'] < 0) {
                    throw ValidationException::withMessages(['items' => ["Only {$left} {$dish->name} left today at {$branch}."]]);
                }
                StockMovement::create([
                    'item_id' => $dish->id,
                    'store_id' => $storeId,
                    'type' => StockMovement::TYPE_PREPARED,
                    'qty' => $line['qty'],
                    'note' => $line['qty'] < 0 ? 'Plates taken off' : 'Plates prepared',
                    'user_id' => $user->id,
                    'occurred_at' => now(),
                ]);
            }
        });

        return $this->index($request);
    }
}
