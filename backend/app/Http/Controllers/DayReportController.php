<?php

namespace App\Http\Controllers;

use App\Models\Expense;
use App\Models\Sale;
use App\Models\SaleItem;
use App\Models\Store;
use App\Models\User;
use Carbon\CarbonImmutable;
use Illuminate\Http\Request;

/**
 * One person's day (or, for a manager, the whole branch's day): every item
 * and drink sold, how it was paid, discounts, cancelled sales, expenses and
 * the cash to hand over. The app turns it into the "My day" PDF.
 */
class DayReportController extends Controller
{
    public function show(Request $request)
    {
        $viewer = $request->user();
        $tz = config('app.business_timezone', 'Africa/Kampala');
        $day = CarbonImmutable::parse($request->input('date', now($tz)->toDateString()), $tz)->startOfDay();
        $bounds = [$day->utc(), $day->endOfDay()->utc()];

        $person = $viewer;
        if ($request->filled('user_id') && $request->integer('user_id') !== $viewer->id) {
            $person = User::findOrFail($request->integer('user_id'));
            $sameBranch = $viewer->role === User::ROLE_STORE_MANAGER && $person->store_id === $viewer->store_id;
            if (! $viewer->isAdmin() && ! $sameBranch) {
                abort(403, 'You can only see your own day.');
            }
        }
        $branchWide = $request->input('scope') === 'branch'
            && ($viewer->isAdmin() || $viewer->role === User::ROLE_STORE_MANAGER);
        $storeId = $viewer->isAdmin() && $request->filled('store_id') ? $request->integer('store_id') : $person->store_id;

        $sales = Sale::query()
            ->with(['items.item:id,name,sell_category,is_drink', 'customer:id,name'])
            ->whereBetween('sold_at', $bounds)
            ->when($branchWide, fn ($q) => $q->where('store_id', $storeId), fn ($q) => $q->where('sold_by', $person->id))
            ->orderBy('sold_at')
            ->get();
        $counted = $sales->whereNull('voided_at');

        $lines = $counted->flatMap->items->groupBy(fn (SaleItem $l) => $l->item_id ?? 'plate')
            ->map(function ($group) {
                $first = $group->first();
                $item = $first->item;

                return [
                    'name' => $item?->name ?? 'Plate',
                    'category' => $item?->sell_category ?? ($item?->is_drink ? 'Drinks' : ($item ? 'Other' : 'Lunch')),
                    'qty' => (float) $group->sum('qty'),
                    'revenue' => (float) $group->sum('line_total'),
                ];
            })
            ->sortBy([['category', 'asc'], ['revenue', 'desc']])
            ->values();

        $expenses = Expense::query()->with('recordedBy:id,name')
            ->whereBetween('spent_at', $bounds)
            ->when($branchWide, fn ($q) => $q->where('store_id', $storeId), fn ($q) => $q->where('recorded_by', $person->id))
            ->orderBy('spent_at')->get();
        $countedExpenses = $expenses->whereNull('voided_at');

        $cashSales = (float) $counted->where('payment_method', Sale::PAYMENT_CASH)->sum('total');
        $cashExpenses = (float) $countedExpenses->where('paid_from', 'cash')->sum('amount');

        return response()->json([
            'date' => $day->toDateString(),
            'scope' => $branchWide ? 'branch' : 'person',
            'person' => ['id' => $person->id, 'name' => $person->name, 'role' => $person->role],
            'store' => ['id' => $storeId, 'name' => Store::find($storeId)?->name],
            'sales_count' => $counted->count(),
            'gross' => (float) $counted->sum(fn ($s) => (float) $s->total + (float) $s->discount),
            'discounts' => (float) $counted->sum('discount'),
            'total' => (float) $counted->sum('total'),
            'plates' => (float) $counted->flatMap->items->where('item_type', SaleItem::TYPE_PLATE)->sum('qty'),
            'by_payment' => $counted->groupBy('payment_method')
                ->map(fn ($g, $method) => ['method' => $method, 'count' => $g->count(), 'total' => (float) $g->sum('total')])
                ->values(),
            'items' => $lines,
            'discounted_sales' => $counted->where('discount', '>', 0)->map(fn (Sale $s) => [
                'id' => $s->id, 'discount' => (float) $s->discount, 'note' => $s->discount_note, 'sold_at' => $s->sold_at,
            ])->values(),
            'cancelled_sales' => $sales->whereNotNull('voided_at')->map(fn (Sale $s) => [
                'id' => $s->id, 'total' => (float) $s->total, 'reason' => $s->void_reason, 'sold_at' => $s->sold_at,
            ])->values(),
            'expenses' => $countedExpenses->map(fn (Expense $e) => [
                'id' => $e->id, 'amount' => (float) $e->amount, 'category' => $e->category, 'note' => $e->note,
                'paid_from' => $e->paid_from, 'spent_at' => $e->spent_at, 'recorded_by' => $e->recordedBy?->name,
            ])->values(),
            'expenses_total' => (float) $countedExpenses->sum('amount'),
            'cash_sales' => $cashSales,
            'cash_expenses' => $cashExpenses,
            'cash_to_hand_over' => $cashSales - $cashExpenses,
        ]);
    }
}
