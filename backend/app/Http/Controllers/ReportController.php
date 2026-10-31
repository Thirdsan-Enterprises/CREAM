<?php

namespace App\Http\Controllers;

use App\Models\CateringOrder;
use App\Models\Customer;
use App\Models\Sale;
use App\Models\SaleItem;
use App\Models\Store;
use App\Services\CustomerStanding;
use App\Services\StockService;
use Illuminate\Http\Request;

class ReportController extends Controller
{
    public function __construct(private readonly StockService $stockService) {}

    public function dashboard()
    {
        $todaySales = Sale::query()->counted()->whereDate('sold_at', now()->toDateString())->with('items')->get();

        $salesByStore = $todaySales->groupBy('store_id')->map(fn ($sales) => [
            'total' => $sales->sum('total'),
            'count' => $sales->count(),
        ]);

        $platesSoldToday = $todaySales->flatMap->items
            ->where('item_type', SaleItem::TYPE_PLATE)
            ->sum('qty');

        return response()->json([
            'sales_total_today' => $todaySales->sum('total'),
            'plates_sold_today' => (float) $platesSoldToday,
            'sales_by_store_today' => (object) $salesByStore->all(),
            'low_stock_alerts' => $this->lowStockAlerts(),
            'upcoming_catering' => $this->upcomingCateringOrders(7),
            'total_outstanding_credit' => $this->totalOutstandingCredit(),
            'accounts_needing_attention' => $this->accountsNeedingAttention(),
        ]);
    }

    public function stockStatus()
    {
        $stores = Store::query()->where('is_active', true)->get();

        return response()->json(
            $stores->map(fn (Store $store) => [
                'store_id' => $store->id,
                'store_name' => $store->name,
                'items' => $this->stockService->storeItemStatuses($store->id),
            ])->values()
        );
    }

    public function outstandingCredit()
    {
        $customers = Customer::query()->where('account_type', Customer::TYPE_CREDIT)->with(['ledgerEntries', 'store:id,name'])->get();
        $standing = app(CustomerStanding::class);

        $outstanding = $customers->map(function (Customer $customer) use ($standing) {
            $balance = $customer->balance();
            $state = $standing->for($customer, $balance);
            $lastDeposit = $customer->ledgerEntries()
                ->where('type', 'deposit')
                ->orderByDesc('occurred_at')
                ->first();

            $since = $lastDeposit?->occurred_at ?? $customer->created_at;

            return [
                'customer_id' => $customer->id,
                'name' => $customer->name,
                'phone' => $customer->phone,
                'balance' => $balance,
                'credit_limit' => (float) $customer->credit_limit,
                'credit_used_pct' => $state['credit_used_pct'],
                'status' => $state['status'],
                'store_name' => $customer->store?->name,
                'days_since_last_payment' => now()->diffInDays($since),
            ];
        })->filter(fn ($row) => $row['balance'] < 0)->values();

        return response()->json($outstanding);
    }

    public function cateringPipeline(Request $request)
    {
        $query = CateringOrder::query()->with('package')->orderBy('event_date');

        if ($request->filled('status')) {
            $query->where('status', $request->string('status'));
        }

        if ($request->boolean('upcoming')) {
            $query->where('event_date', '>=', now()->toDateString())
                ->whereNotIn('status', [CateringOrder::STATUS_SETTLED, CateringOrder::STATUS_CANCELLED]);
        }

        return response()->json(
            $query->get()->map(fn (CateringOrder $order) => [
                'id' => $order->id,
                'client_name' => $order->client_name,
                'event_name' => $order->event_name,
                'event_date' => $order->event_date->toDateString(),
                'package' => $order->package->name,
                'number_of_plates' => $order->number_of_plates,
                'total_amount' => (float) $order->total_amount,
                'balance_due' => $order->balanceDue(),
                'status' => $order->status,
            ])
        );
    }

    private function lowStockAlerts(): array
    {
        $alerts = [];

        foreach (Store::query()->where('is_active', true)->get() as $store) {
            foreach ($this->stockService->storeItemStatuses($store->id) as $row) {
                if ($row['status'] === 'Re-Order') {
                    $alerts[] = [...$row, 'store_id' => $store->id, 'store_name' => $store->name];
                }
            }
        }

        return $alerts;
    }

    private function upcomingCateringOrders(int $days): array
    {
        return CateringOrder::query()
            ->with('package')
            ->whereDate('event_date', '>=', now()->toDateString())
            ->whereDate('event_date', '<=', now()->addDays($days)->toDateString())
            ->whereNotIn('status', [CateringOrder::STATUS_SETTLED, CateringOrder::STATUS_CANCELLED])
            ->orderBy('event_date')
            ->get()
            ->map(fn (CateringOrder $order) => [
                'id' => $order->id,
                'client_name' => $order->client_name,
                'event_name' => $order->event_name,
                'event_date' => $order->event_date->toDateString(),
                'package' => $order->package->name,
                'status' => $order->status,
            ])->values()->all();
    }

    private function totalOutstandingCredit(): float
    {
        $total = 0;

        foreach (Customer::query()->where('account_type', Customer::TYPE_CREDIT)->get() as $customer) {
            $balance = $customer->balance();
            if ($balance < 0) {
                $total += abs($balance);
            }
        }

        return $total;
    }

    /**
     * Accounts staff should know about before charging: credit customers at
     * 80%+ of their limit, and prepaid/LPO accounts that cannot cover a plate.
     */
    private function accountsNeedingAttention(): array
    {
        $standing = app(CustomerStanding::class);

        return Customer::query()
            ->where('is_active', true)
            ->with('store:id,name')
            ->withSum('ledgerEntries as balance', 'amount')
            // An account never used yet is not a warning.
            ->whereHas('ledgerEntries')
            ->get()
            ->map(fn (Customer $c) => [
                'customer_id' => $c->id,
                'name' => $c->name,
                'account_type' => $c->account_type,
                'store_name' => $c->store?->name,
                ...$standing->for($c, (float) $c->balance),
            ])
            ->filter(fn ($row) => $row['status'] !== 'ok')
            // Credit customers who owe money first: they matter most.
            ->sortBy(fn ($row) => [$row['status'] === 'blocked' ? 0 : 1, $row['available']])
            ->values()
            ->all();
    }
}
