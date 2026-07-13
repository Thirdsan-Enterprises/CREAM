<?php

namespace App\Http\Controllers;

use App\Models\StockMovement;
use App\Models\StockTransfer;
use App\Models\Store;
use App\Support\StoreScope;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\ValidationException;

class StockTransferController extends Controller
{
    public function index(Request $request)
    {
        $user = $request->user();

        $query = StockTransfer::query()->with(['fromStore', 'toStore', 'items.item'])->orderByDesc('dispatched_at');

        if (! $user->isAdmin()) {
            $query->where(function ($q) use ($user) {
                $q->where('from_store_id', $user->store_id)
                    ->orWhere('to_store_id', $user->store_id);
            });
        } elseif ($request->filled('store_id')) {
            $storeId = $request->integer('store_id');
            $query->where(function ($q) use ($storeId) {
                $q->where('from_store_id', $storeId)->orWhere('to_store_id', $storeId);
            });
        }

        if ($request->filled('status')) {
            $query->where('status', $request->string('status'));
        }

        return $query->paginate();
    }

    public function show(Request $request, StockTransfer $transfer)
    {
        $this->assertVisible($request->user(), $transfer);

        return $transfer->load(['fromStore', 'toStore', 'items.item', 'dispatchedBy', 'confirmedBy']);
    }

    public function store(Request $request)
    {
        $user = $request->user();

        $data = $request->validate([
            'to_store_id' => ['required', 'exists:stores,id', 'different:from_store_id'],
            'items' => ['required', 'array', 'min:1'],
            'items.*.item_id' => ['required', 'exists:items,id'],
            'items.*.qty' => ['required', 'numeric', 'gt:0'],
        ]);

        $fromStore = Store::where('is_main', true)->firstOrFail();

        if (! $user->isAdmin() && $user->store_id !== $fromStore->id) {
            abort(403, 'Only the main store can dispatch transfers.');
        }

        $transfer = DB::transaction(function () use ($data, $fromStore, $user) {
            $transfer = StockTransfer::create([
                'from_store_id' => $fromStore->id,
                'to_store_id' => $data['to_store_id'],
                'status' => StockTransfer::STATUS_DISPATCHED,
                'dispatched_by' => $user->id,
                'dispatched_at' => now(),
            ]);

            foreach ($data['items'] as $line) {
                $transfer->items()->create([
                    'item_id' => $line['item_id'],
                    'qty_dispatched' => $line['qty'],
                ]);

                StockMovement::create([
                    'item_id' => $line['item_id'],
                    'store_id' => $fromStore->id,
                    'type' => StockMovement::TYPE_TRANSFER_OUT,
                    'qty' => -abs($line['qty']),
                    'related_transfer_id' => $transfer->id,
                    'user_id' => $user->id,
                    'occurred_at' => now(),
                ]);
            }

            return $transfer;
        });

        return response()->json($transfer->load('items.item'), 201);
    }

    public function confirm(Request $request, StockTransfer $transfer)
    {
        $user = $request->user();

        if ($transfer->status !== StockTransfer::STATUS_DISPATCHED) {
            throw ValidationException::withMessages([
                'status' => ['This transfer has already been confirmed.'],
            ]);
        }

        StoreScope::assertAccess($user, $transfer->to_store_id);

        $data = $request->validate([
            'items' => ['required', 'array', 'min:1'],
            'items.*.stock_transfer_item_id' => ['required', 'exists:stock_transfer_items,id'],
            'items.*.qty_received' => ['required', 'numeric', 'min:0'],
        ]);

        $transfer = DB::transaction(function () use ($data, $transfer, $user) {
            foreach ($data['items'] as $line) {
                $transferItem = $transfer->items()->whereKey($line['stock_transfer_item_id'])->lockForUpdate()->firstOrFail();

                if ($transferItem->qty_received !== null) {
                    throw ValidationException::withMessages([
                        'items' => ["Transfer line {$transferItem->id} has already been confirmed."],
                    ]);
                }

                $transferItem->update(['qty_received' => $line['qty_received']]);

                StockMovement::create([
                    'item_id' => $transferItem->item_id,
                    'store_id' => $transfer->to_store_id,
                    'type' => StockMovement::TYPE_TRANSFER_IN,
                    'qty' => abs($line['qty_received']),
                    'related_transfer_id' => $transfer->id,
                    'user_id' => $user->id,
                    'occurred_at' => now(),
                ]);
            }

            $allItems = $transfer->items()->get();

            if ($allItems->contains(fn ($i) => $i->qty_received === null)) {
                return $transfer;
            }

            $hasDiscrepancy = $allItems->contains(
                fn ($i) => round((float) $i->qty_received - (float) $i->qty_dispatched, 2) !== 0.0
            );

            $transfer->update([
                'status' => $hasDiscrepancy ? StockTransfer::STATUS_DISCREPANCY : StockTransfer::STATUS_CONFIRMED,
                'confirmed_by' => $user->id,
                'confirmed_at' => now(),
            ]);

            return $transfer;
        });

        return $transfer->load('items.item');
    }

    private function assertVisible($user, StockTransfer $transfer): void
    {
        if ($user->isAdmin()) {
            return;
        }

        if (! in_array($user->store_id, [$transfer->from_store_id, $transfer->to_store_id], true)) {
            abort(403, 'You do not have access to this transfer.');
        }
    }
}
