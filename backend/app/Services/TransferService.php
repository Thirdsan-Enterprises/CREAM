<?php

namespace App\Services;

use App\Models\Item;
use App\Models\ItemStoreSetting;
use App\Models\StockMovement;
use App\Models\StockTransfer;
use App\Models\Store;
use App\Models\User;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\ValidationException;

/**
 * Sending stock from the procurement unit to a branch. The stock leaves the
 * main store now; the branch confirms what arrived.
 */
class TransferService
{
    public function __construct(private readonly StockService $stockService) {}

    /**
     * @param  array<int, array{item_id: int, qty: float}>  $lines
     */
    public function dispatch(User $user, Store $from, int $toStoreId, array $lines): StockTransfer
    {
        if ($from->id === $toStoreId) {
            throw ValidationException::withMessages(['to_store_id' => ['Choose a branch other than '.$from->name.'.']]);
        }

        return DB::transaction(function () use ($user, $from, $toStoreId, $lines) {
            // Lines for the same item are added up and checked together.
            $wanted = [];
            foreach ($lines as $line) {
                $wanted[$line['item_id']] = ($wanted[$line['item_id']] ?? 0) + (float) $line['qty'];
            }
            foreach ($wanted as $itemId => $qty) {
                ItemStoreSetting::where('item_id', $itemId)->where('store_id', $from->id)->lockForUpdate()->first();
                $balance = $this->stockService->balance($itemId, $from->id);
                if ($qty > $balance) {
                    $item = Item::find($itemId);
                    throw ValidationException::withMessages([
                        'items' => ["Only {$balance} {$item?->unit} of {$item?->name} available at {$from->name}: cannot send {$qty}."],
                    ]);
                }
            }

            $transfer = StockTransfer::create([
                'from_store_id' => $from->id,
                'to_store_id' => $toStoreId,
                'status' => StockTransfer::STATUS_DISPATCHED,
                'dispatched_by' => $user->id,
                'dispatched_at' => now(),
            ]);

            foreach ($lines as $line) {
                $transfer->items()->create([
                    'item_id' => $line['item_id'],
                    'qty_dispatched' => $line['qty'],
                ]);

                StockMovement::create([
                    'item_id' => $line['item_id'],
                    'store_id' => $from->id,
                    'type' => StockMovement::TYPE_TRANSFER_OUT,
                    'qty' => -abs((float) $line['qty']),
                    'related_transfer_id' => $transfer->id,
                    'user_id' => $user->id,
                    'occurred_at' => now(),
                ]);
            }

            return $transfer;
        });
    }
}
