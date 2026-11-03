<?php

namespace App\Http\Controllers;

use App\Models\Sale;
use App\Support\StoreScope;
use Illuminate\Http\Request;

/**
 * Everything a customer receipt shows, for printing or sending after a
 * sale and for reprinting later. This is a customer receipt, not a URA
 * EFRIS fiscal receipt.
 */
class ReceiptController extends Controller
{
    public function show(Request $request, Sale $sale)
    {
        StoreScope::assertAccess($request->user(), $sale->store_id);
        $sale->load(['store', 'soldBy:id,name', 'customer', 'items.item:id,name,unit']);

        return response()->json([
            'number' => $sale->id,
            'sold_at' => $sale->sold_at,
            'store' => [
                'name' => $sale->store->name,
                'address' => $sale->store->address,
                'phone' => $sale->store->phone,
            ],
            'cashier' => $sale->soldBy?->name,
            'lines' => $sale->items->map(fn ($line) => [
                'name' => $line->item?->name ?? 'Plate',
                'qty' => (float) $line->qty,
                'unit_price' => (float) $line->unit_price,
                'total' => (float) $line->line_total,
            ])->values(),
            'subtotal' => (float) $sale->total + (float) $sale->discount,
            'discount' => (float) $sale->discount,
            'discount_note' => $sale->discount_note,
            'total' => (float) $sale->total,
            'payment_method' => $sale->payment_method,
            'customer' => $sale->customer ? [
                'name' => $sale->customer->name,
                'account_type' => $sale->customer->account_type,
                'balance' => $sale->customer->balance(),
            ] : null,
            'voided' => $sale->voided_at !== null,
            'void_reason' => $sale->void_reason,
        ]);
    }
}
