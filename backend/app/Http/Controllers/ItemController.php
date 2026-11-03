<?php

namespace App\Http\Controllers;

use App\Models\EditLog;
use App\Models\Item;
use App\Models\ItemStoreSetting;
use App\Services\StockService;
use Illuminate\Http\Request;
use Illuminate\Support\Arr;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\ValidationException;

class ItemController extends Controller
{
    public function __construct(private readonly StockService $stockService) {}

    public function index(Request $request)
    {
        $query = Item::query()->orderBy('name');

        // The stock list: things bought and counted. Dishes made to order
        // (lunch, tea) live on the menu only; ?all=1 includes them.
        if (! $request->boolean('all')) {
            $query->where('tracks_stock', true);
        }
        // Removed items stay in history but leave the lists.
        if (! $request->boolean('include_removed') && ! $request->has('is_active')) {
            $query->where('is_active', true);
        }

        if ($request->boolean('is_drink', false) && $request->has('is_drink')) {
            $query->where('is_drink', $request->boolean('is_drink'));
        }

        if ($request->has('is_active')) {
            $query->where('is_active', $request->boolean('is_active'));
        }

        return $query->paginate($this->perPage($request, 500));
    }

    public function store(Request $request)
    {
        $this->assertCanManage($request);
        $data = $request->validate([
            'name' => ['required', 'string', 'max:255'],
            'unit' => ['required', 'string', 'max:50'],
            'category' => ['nullable', 'string', 'max:100'],
            'is_drink' => ['boolean'],
            'is_active' => ['boolean'],
            'safety_stock' => ['nullable', 'numeric', 'min:0'],
        ]);

        $exists = Item::where('tracks_stock', true)->where('is_sellable', false)
            ->whereRaw('LOWER(name) = ?', [mb_strtolower(trim($data['name']))])->first();
        if ($exists) {
            throw ValidationException::withMessages([
                'name' => [$exists->is_active
                    ? "{$exists->name} is already in kitchen stock."
                    : "{$exists->name} was removed earlier: add it back from the removed items instead."],
            ]);
        }

        $item = DB::transaction(function () use ($data) {
            $item = Item::create([...Arr::except($data, 'safety_stock'), 'name' => trim($data['name']), 'tracks_stock' => true]);
            ItemStoreSetting::backfillForItem($item, (float) ($data['safety_stock'] ?? 0));

            return $item;
        });

        return response()->json($item, 201);
    }

    public function update(Request $request, Item $item)
    {
        $this->assertCanManage($request);
        $data = $request->validate([
            'name' => ['sometimes', 'string', 'max:255'],
            'unit' => ['sometimes', 'string', 'max:50'],
            'category' => ['nullable', 'string', 'max:100'],
            'is_drink' => ['sometimes', 'boolean'],
            'is_active' => ['sometimes', 'boolean'],
            'reason' => ['nullable', 'string', 'max:500'],
        ]);
        $reason = trim($data['reason'] ?? '');
        unset($data['reason']);

        $fields = ['name', 'unit', 'category', 'is_active'];
        $before = $item->only($fields);
        $item->fill($data);
        $changes = EditLog::diff($before, $item->only($fields));

        DB::transaction(function () use ($item, $changes, $reason, $request) {
            $item->save();
            if ($changes) {
                EditLog::record(
                    $request->user(), 'stock_item', $item->id, 'Kitchen stock: '.$item->name,
                    isset($changes['is_active']) && $item->is_active ? 'restored' : 'edited',
                    $changes, $reason !== '' ? $reason : 'Details updated',
                );
            }
        });

        return $item;
    }

    /**
     * Take an item off the kitchen stock list. One that was never bought,
     * sent, used or sold is deleted; otherwise it is kept for the records
     * and hidden, and can be added back.
     */
    public function destroy(Request $request, Item $item)
    {
        $this->assertCanManage($request);
        $data = $request->validate(['reason' => ['required', 'string', 'max:500']], [
            'reason.required' => 'Say why this item is being removed.',
        ]);
        if ($item->is_sellable) {
            throw ValidationException::withMessages(['item' => ["{$item->name} is on the menu: take it off the menu in Prices & menu."]]);
        }

        $used = DB::table('stock_movements')->where('item_id', $item->id)->exists()
            || DB::table('stock_transfer_items')->where('item_id', $item->id)->exists()
            || DB::table('stock_request_items')->where('item_id', $item->id)->exists()
            || DB::table('sale_items')->where('item_id', $item->id)->exists();

        DB::transaction(function () use ($item, $used, $data, $request) {
            EditLog::record(
                $request->user(), 'stock_item', $item->id, 'Kitchen stock: '.$item->name,
                $used ? 'removed' : 'deleted', ['is_active' => ['from' => true, 'to' => false]], $data['reason'],
            );
            $used ? $item->update(['is_active' => false]) : $item->delete();
        });

        return response()->json([
            'deleted' => ! $used,
            'message' => $used
                ? "{$item->name} is removed from the lists; its history is kept."
                : "{$item->name} is deleted.",
        ]);
    }

    /** Kitchen stock is managed by the owner and the procurement unit. */
    private function assertCanManage(Request $request): void
    {
        $user = $request->user();
        if (! $user->isAdmin() && ! $user->isProcurement()) {
            abort(403, 'Only the owner and procurement manage kitchen stock items.');
        }
    }

    public function balances(Item $item)
    {
        return response()->json([
            'item' => $item,
            'balances' => $this->stockService->balances($item->id),
        ]);
    }

    public function setStoreSettings(Request $request, Item $item)
    {
        $this->assertCanManage($request);
        $data = $request->validate([
            'store_id' => ['required', 'exists:stores,id'],
            'safety_stock' => ['required', 'numeric', 'min:0'],
        ]);

        $setting = ItemStoreSetting::updateOrCreate(
            ['item_id' => $item->id, 'store_id' => $data['store_id']],
            ['safety_stock' => $data['safety_stock']],
        );

        return response()->json($setting, 200);
    }
}
