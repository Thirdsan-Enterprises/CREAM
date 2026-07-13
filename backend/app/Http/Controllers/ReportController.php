<?php

namespace App\Http\Controllers;

use App\Models\CateringOrder;
use App\Models\Customer;
use App\Models\ItemStoreSetting;
use App\Models\Sale;
use App\Models\SaleItem;
use App\Models\StockMovement;
use App\Models\Store;
use Illuminate\Http\Request;

class ReportController extends Controller
{
    public function dashboard()
    {
        $todaySales = Sale::query()->whereDate('sold_at', now()->toDateString())->with('items')->get();

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
            'sales_by_store_today' => $salesByStore,
            'low_stock_alerts' => $this->lowStockAlerts(),
            'upcoming_catering' => $this->upcomingCateringOrders(7),
            'total_outstanding_credit' => $this->totalOutstandingCredit(),
        ]);
    }

    public function stockStatus()
    {
        $stores = Store::query()->where('is_active', true)->get();

        return response()->json(
            $stores->map(fn (Store $store) => [
                'store_id' => $store->id,
                'store_name' => $store->name,
                'items' => $this->storeItemStatuses($store->id),
            ])->values()
        );
    }

    public function outstandingCredit()
    {
        $customers = Customer::query()->where('account_type', Customer::TYPE_CREDIT)->with('ledgerEntries')->get();

        $outstanding = $customers->map(function (Customer $customer) {
            $balance = $customer->balance();
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
            foreach ($this->storeItemStatuses($store->id) as $row) {
                if ($row['status'] === 'Re-Order') {
                    $alerts[] = [...$row, 'store_id' => $store->id, 'store_name' => $store->name];
                }
            }
        }

        return $alerts;
    }

    private function storeItemStatuses(int $storeId): array
    {
        $settings = ItemStoreSetting::query()->where('store_id', $storeId)->with('item')->get();

        $balances = StockMovement::query()
            ->where('store_id', $storeId)
            ->selectRaw('item_id, SUM(qty) as balance')
            ->groupBy('item_id')
            ->pluck('balance', 'item_id');

        return $settings->map(function ($setting) use ($balances) {
            $balance = (float) ($balances[$setting->item_id] ?? 0);

            return [
                'item_id' => $setting->item_id,
                'item_name' => $setting->item->name,
                'balance' => $balance,
                'safety_stock' => (float) $setting->safety_stock,
                'status' => $balance <= (float) $setting->safety_stock ? 'Re-Order' : 'Stock Sufficient',
            ];
        })->values()->all();
    }

    private function upcomingCateringOrders(int $days): array
    {
        return CateringOrder::query()
            ->with('package')
            ->whereBetween('event_date', [now()->toDateString(), now()->addDays($days)->toDateString()])
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
}
