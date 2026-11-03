<?php

namespace App\Http\Controllers;

use App\Models\StockMovement;
use Carbon\CarbonImmutable;
use Illuminate\Http\Request;

/**
 * The procurement ledger: every purchase with what was paid and to whom,
 * with totals by heading and by item, for the owner and procurement.
 */
class PurchaseLedgerController extends Controller
{
    public function index(Request $request)
    {
        $user = $request->user();
        if (! $user->isAdmin() && ! $user->isProcurement()) {
            abort(403, 'Only the owner and procurement see the purchases ledger.');
        }
        $tz = config('app.business_timezone', 'Africa/Kampala');
        $from = CarbonImmutable::parse($request->input('from', now($tz)->startOfMonth()->toDateString()), $tz)->startOfDay();
        $to = CarbonImmutable::parse($request->input('to', now($tz)->toDateString()), $tz)->endOfDay();

        $rows = StockMovement::query()
            ->with(['item:id,name,unit,category,is_drink', 'store:id,name', 'user:id,name'])
            ->where('type', StockMovement::TYPE_PURCHASE)
            ->whereBetween('occurred_at', [$from->utc(), $to->utc()])
            ->when($request->filled('store_id'), fn ($q) => $q->where('store_id', $request->integer('store_id')))
            ->when($request->filled('item_id'), fn ($q) => $q->where('item_id', $request->integer('item_id')))
            ->orderByDesc('occurred_at')->orderByDesc('id')
            ->get()
            ->map(fn (StockMovement $m) => [
                'id' => $m->id,
                'occurred_at' => $m->occurred_at,
                'item_id' => $m->item_id,
                'item' => $m->item?->name,
                'unit' => $m->item?->unit,
                'category' => $m->item?->category ?? ($m->item?->is_drink ? 'Drinks' : 'Other'),
                'qty' => (float) $m->qty,
                'unit_cost' => $m->unit_cost === null ? null : (float) $m->unit_cost,
                'total' => $m->unit_cost === null ? null : round((float) $m->unit_cost * (float) $m->qty, 2),
                'supplier' => $m->supplier,
                'store' => $m->store?->name,
                'recorded_by' => $m->user?->name,
                'note' => $m->note,
            ]);

        $priced = $rows->whereNotNull('total');

        return response()->json([
            'from' => $from->toDateString(),
            'to' => $to->toDateString(),
            'total_spent' => (float) $priced->sum('total'),
            'purchases' => $rows->count(),
            'without_price' => $rows->whereNull('total')->count(),
            'by_category' => $priced->groupBy('category')->map(fn ($g, $c) => ['category' => $c, 'total' => (float) $g->sum('total')])
                ->sortByDesc('total')->values(),
            'by_item' => $priced->groupBy('item_id')->map(fn ($g) => [
                'item' => $g->first()['item'],
                'unit' => $g->first()['unit'],
                'qty' => (float) $g->sum('qty'),
                'total' => (float) $g->sum('total'),
                'average_unit_cost' => $g->sum('qty') > 0 ? round($g->sum('total') / $g->sum('qty'), 2) : null,
            ])->sortByDesc('total')->values(),
            'rows' => $rows->values(),
        ]);
    }
}
