<?php

namespace App\Services;

use App\Models\SaleItem;
use App\Models\StockMovement;
use App\Models\StockTransfer;
use App\Models\Store;
use Carbon\CarbonImmutable;
use Illuminate\Support\Collection;
use Illuminate\Support\Facades\DB;

/**
 * Per-branch revenue and activity for the owner's Branches view.
 *
 * Periods are whole business days in config('app.business_timezone');
 * sold_at is stored in UTC, so boundaries are converted before querying
 * and each sale is bucketed by its local day/hour afterwards. Aggregation
 * happens in PHP over plain rows so it behaves the same on MySQL and the
 * SQLite test database.
 */
class BranchPerformanceService
{
    public function __construct(private readonly StockService $stockService) {}

    /**
     * @return array{from: CarbonImmutable, to: CarbonImmutable, days: int}
     */
    public function period(?string $from, ?string $to): array
    {
        $tz = $this->timezone();
        $today = CarbonImmutable::now($tz)->startOfDay();

        $fromDay = $from ? CarbonImmutable::createFromFormat('Y-m-d', $from, $tz)->startOfDay() : $today;
        $toDay = $to ? CarbonImmutable::createFromFormat('Y-m-d', $to, $tz)->startOfDay() : $fromDay;

        return [
            'from' => $fromDay,
            'to' => $toDay,
            'days' => (int) $fromDay->diffInDays($toDay) + 1,
        ];
    }

    public function overview(array $period): array
    {
        $previous = $this->previousPeriod($period);

        $sales = $this->salesRows($period);
        $items = $this->saleItemRows($period);
        $previousRevenue = $this->revenueByStore($previous);

        $storeIds = $sales->pluck('store_id')->unique();
        $stores = Store::query()
            ->where(fn ($q) => $q->where('is_active', true)->orWhereIn('id', $storeIds))
            ->orderByDesc('is_main')
            ->orderBy('name')
            ->get();

        $grandTotal = (float) $sales->sum('total');
        $lastSaleAt = DB::table('sales')
            ->selectRaw('store_id, MAX(sold_at) as last_sale_at')
            ->groupBy('store_id')
            ->pluck('last_sale_at', 'store_id');

        $branches = $stores->map(function (Store $store) use ($sales, $items, $previousRevenue, $grandTotal, $lastSaleAt) {
            $storeSales = $sales->where('store_id', $store->id);
            $storeItems = $items->where('store_id', $store->id);
            $reorder = collect($this->stockService->storeItemStatuses($store->id))
                ->where('status', 'Re-Order')
                ->count();

            return [
                'store_id' => $store->id,
                'store_name' => $store->name,
                'is_main' => (bool) $store->is_main,
                ...$this->totals($storeSales, $storeItems, (float) ($previousRevenue[$store->id] ?? 0)),
                'share_pct' => $grandTotal > 0 ? round((float) $storeSales->sum('total') / $grandTotal * 100, 1) : 0.0,
                'by_payment_method' => (object) $this->byPaymentMethod($storeSales)
                    ->mapWithKeys(fn ($row) => [$row['method'] => $row['revenue']])
                    ->all(),
                'reorder_items_count' => $reorder,
                'last_sale_at' => isset($lastSaleAt[$store->id])
                    ? $this->toIso($lastSaleAt[$store->id])
                    : null,
            ];
        })->values();

        return [
            'period' => $this->describePeriod($period),
            'previous_period' => $this->describePeriod($previous),
            'totals' => $this->totals($sales, $items, (float) $previousRevenue->sum()),
            'daily' => $this->daily($period, $sales, $items, perStore: true),
            'hourly' => $this->hourly($sales, perStore: true),
            'branches' => $branches,
        ];
    }

    public function branch(Store $store, array $period): array
    {
        $previous = $this->previousPeriod($period);

        $sales = $this->salesRows($period, $store->id);
        $items = $this->saleItemRows($period, $store->id);
        $previousRevenue = (float) ($this->revenueByStore($previous, $store->id)[$store->id] ?? 0);

        $stock = collect($this->stockService->storeItemStatuses($store->id));

        return [
            'store' => [
                'id' => $store->id,
                'name' => $store->name,
                'is_main' => (bool) $store->is_main,
            ],
            'period' => $this->describePeriod($period),
            'previous_period' => $this->describePeriod($previous),
            'totals' => $this->totals($sales, $items, $previousRevenue),
            'daily' => $this->daily($period, $sales, $items, perStore: false),
            'hourly' => $this->hourly($sales, perStore: false),
            'by_payment_method' => $this->byPaymentMethod($sales)->values(),
            'by_cashier' => $this->byCashier($sales, $items),
            'drinks' => $this->drinks($items),
            'stock_used' => $this->stockUsed($period, $store->id),
            'stock' => [
                'reorder_count' => $stock->where('status', 'Re-Order')->count(),
                'sufficient_count' => $stock->where('status', '!=', 'Re-Order')->count(),
                'reorder_items' => $stock->where('status', 'Re-Order')
                    ->sortBy(fn ($row) => $row['balance'] - $row['safety_stock'])
                    ->values(),
            ],
            'transfers' => $this->transfers($period, $store->id),
            'recent_sales' => $this->recentSales($period, $store->id),
        ];
    }

    private function timezone(): string
    {
        return config('app.business_timezone', 'UTC');
    }

    /** UTC bounds, formatted the way Eloquent stores datetimes. */
    private function bounds(array $period): array
    {
        return [
            $period['from']->startOfDay()->utc()->format('Y-m-d H:i:s'),
            $period['to']->endOfDay()->utc()->format('Y-m-d H:i:s'),
        ];
    }

    private function previousPeriod(array $period): array
    {
        return [
            'from' => $period['from']->subDays($period['days']),
            'to' => $period['from']->subDay(),
            'days' => $period['days'],
        ];
    }

    private function describePeriod(array $period): array
    {
        return [
            'from' => $period['from']->toDateString(),
            'to' => $period['to']->toDateString(),
            'days' => $period['days'],
            'timezone' => $this->timezone(),
        ];
    }

    private function local(string $utc): CarbonImmutable
    {
        return CarbonImmutable::parse($utc, 'UTC')->setTimezone($this->timezone());
    }

    private function toIso(string $utc): string
    {
        return CarbonImmutable::parse($utc, 'UTC')->toIso8601ZuluString();
    }

    private function salesRows(array $period, ?int $storeId = null): Collection
    {
        return DB::table('sales')
            ->leftJoin('users', 'users.id', '=', 'sales.sold_by')
            ->whereBetween('sales.sold_at', $this->bounds($period))
            ->when($storeId, fn ($q) => $q->where('sales.store_id', $storeId))
            ->orderBy('sales.sold_at')
            ->get([
                'sales.id', 'sales.store_id', 'sales.sold_by', 'users.name as sold_by_name',
                'sales.payment_method', 'sales.total', 'sales.sold_at',
            ])
            ->map(function ($row) {
                $row->total = (float) $row->total;
                $row->local = $this->local($row->sold_at);

                return $row;
            });
    }

    private function saleItemRows(array $period, ?int $storeId = null): Collection
    {
        return DB::table('sale_items')
            ->join('sales', 'sales.id', '=', 'sale_items.sale_id')
            ->leftJoin('items', 'items.id', '=', 'sale_items.item_id')
            ->whereBetween('sales.sold_at', $this->bounds($period))
            ->when($storeId, fn ($q) => $q->where('sales.store_id', $storeId))
            ->get([
                'sale_items.sale_id', 'sales.store_id', 'sales.sold_by', 'sales.sold_at',
                'sale_items.item_type', 'sale_items.item_id', 'items.name as item_name',
                'sale_items.qty', 'sale_items.line_total',
            ])
            ->map(function ($row) {
                $row->qty = (float) $row->qty;
                $row->line_total = (float) $row->line_total;
                $row->local = $this->local($row->sold_at);

                return $row;
            });
    }

    private function revenueByStore(array $period, ?int $storeId = null): Collection
    {
        return DB::table('sales')
            ->whereBetween('sold_at', $this->bounds($period))
            ->when($storeId, fn ($q) => $q->where('store_id', $storeId))
            ->selectRaw('store_id, SUM(total) as revenue')
            ->groupBy('store_id')
            ->pluck('revenue', 'store_id')
            ->map(fn ($v) => (float) $v);
    }

    private function totals(Collection $sales, Collection $items, float $previousRevenue): array
    {
        $revenue = (float) $sales->sum('total');
        $plates = $items->where('item_type', SaleItem::TYPE_PLATE);
        $drinks = $items->where('item_type', SaleItem::TYPE_DRINK);
        $count = $sales->count();

        return [
            'revenue' => $revenue,
            'previous_revenue' => $previousRevenue,
            'change_pct' => $previousRevenue > 0
                ? round(($revenue - $previousRevenue) / $previousRevenue * 100, 1)
                : null,
            'sales_count' => $count,
            'average_sale' => $count > 0 ? round($revenue / $count) : 0.0,
            'plates_sold' => (float) $plates->sum('qty'),
            'plate_revenue' => (float) $plates->sum('line_total'),
            'drinks_sold' => (float) $drinks->sum('qty'),
            'drink_revenue' => (float) $drinks->sum('line_total'),
        ];
    }

    private function daily(array $period, Collection $sales, Collection $items, bool $perStore): array
    {
        $salesByDay = $sales->groupBy(fn ($row) => $row->local->toDateString());
        $platesByDay = $items->where('item_type', SaleItem::TYPE_PLATE)
            ->groupBy(fn ($row) => $row->local->toDateString());

        $days = [];
        for ($day = $period['from']; $day->lte($period['to']); $day = $day->addDay()) {
            $key = $day->toDateString();
            $daySales = $salesByDay[$key] ?? collect();

            $row = [
                'date' => $key,
                'revenue' => (float) $daySales->sum('total'),
                'sales_count' => $daySales->count(),
                'plates_sold' => (float) ($platesByDay[$key] ?? collect())->sum('qty'),
            ];

            if ($perStore) {
                $row['by_store'] = (object) $daySales->groupBy('store_id')
                    ->map(fn ($g) => (float) $g->sum('total'))
                    ->all();
            }

            $days[] = $row;
        }

        return $days;
    }

    private function hourly(Collection $sales, bool $perStore): array
    {
        $byHour = $sales->groupBy(fn ($row) => (int) $row->local->format('G'));

        $hours = [];
        for ($hour = 0; $hour < 24; $hour++) {
            $hourSales = $byHour[$hour] ?? collect();

            $row = [
                'hour' => $hour,
                'revenue' => (float) $hourSales->sum('total'),
                'sales_count' => $hourSales->count(),
            ];

            if ($perStore) {
                $row['by_store'] = (object) $hourSales->groupBy('store_id')
                    ->map(fn ($g) => (float) $g->sum('total'))
                    ->all();
            }

            $hours[] = $row;
        }

        return $hours;
    }

    private function byPaymentMethod(Collection $sales): Collection
    {
        return $sales->groupBy('payment_method')
            ->map(fn ($g, $method) => [
                'method' => $method,
                'revenue' => (float) $g->sum('total'),
                'sales_count' => $g->count(),
            ])
            ->sortByDesc('revenue')
            ->values();
    }

    private function byCashier(Collection $sales, Collection $items): Collection
    {
        $platesBySeller = $items->where('item_type', SaleItem::TYPE_PLATE)->groupBy('sold_by');

        return $sales->groupBy('sold_by')
            ->map(fn ($g, $userId) => [
                'user_id' => (int) $userId,
                'name' => $g->first()->sold_by_name ?? 'Unknown',
                'revenue' => (float) $g->sum('total'),
                'sales_count' => $g->count(),
                'plates_sold' => (float) ($platesBySeller[$userId] ?? collect())->sum('qty'),
            ])
            ->sortByDesc('revenue')
            ->values();
    }

    private function drinks(Collection $items): Collection
    {
        return $items->where('item_type', SaleItem::TYPE_DRINK)
            ->groupBy('item_id')
            ->map(fn ($g, $itemId) => [
                'item_id' => (int) $itemId,
                'name' => $g->first()->item_name ?? 'Unknown',
                'qty' => (float) $g->sum('qty'),
                'revenue' => (float) $g->sum('line_total'),
            ])
            ->sortByDesc('qty')
            ->values();
    }

    private function stockUsed(array $period, int $storeId): Collection
    {
        return DB::table('stock_movements')
            ->join('items', 'items.id', '=', 'stock_movements.item_id')
            ->where('stock_movements.store_id', $storeId)
            ->where('stock_movements.type', StockMovement::TYPE_CONSUMPTION)
            ->whereBetween('stock_movements.occurred_at', $this->bounds($period))
            ->groupBy('stock_movements.item_id', 'items.name', 'items.unit', 'items.is_drink')
            ->selectRaw('stock_movements.item_id, items.name, items.unit, items.is_drink, SUM(stock_movements.qty) as qty')
            ->get()
            ->map(fn ($row) => [
                'item_id' => (int) $row->item_id,
                'name' => $row->name,
                'unit' => $row->unit,
                'is_drink' => (bool) $row->is_drink,
                'qty' => abs((float) $row->qty),
            ])
            ->sortByDesc('qty')
            ->values();
    }

    private function transfers(array $period, int $storeId): array
    {
        $bounds = $this->bounds($period);

        $inPeriod = DB::table('stock_transfers')
            ->where(fn ($q) => $q->where('to_store_id', $storeId)->orWhere('from_store_id', $storeId))
            ->whereBetween('dispatched_at', $bounds)
            ->get(['from_store_id', 'to_store_id', 'status']);

        return [
            'received' => $inPeriod->where('to_store_id', $storeId)
                ->whereIn('status', [StockTransfer::STATUS_CONFIRMED, StockTransfer::STATUS_DISCREPANCY])
                ->count(),
            'with_discrepancy' => $inPeriod->where('to_store_id', $storeId)
                ->where('status', StockTransfer::STATUS_DISCREPANCY)
                ->count(),
            'dispatched' => $inPeriod->where('from_store_id', $storeId)->count(),
            // Awaiting confirmation right now, regardless of period: these
            // are the ones a manager still has to act on.
            'awaiting_confirmation' => DB::table('stock_transfers')
                ->where('to_store_id', $storeId)
                ->where('status', StockTransfer::STATUS_DISPATCHED)
                ->count(),
        ];
    }

    private function recentSales(array $period, int $storeId): Collection
    {
        $sales = DB::table('sales')
            ->leftJoin('users', 'users.id', '=', 'sales.sold_by')
            ->leftJoin('customers', 'customers.id', '=', 'sales.customer_id')
            ->where('sales.store_id', $storeId)
            ->whereBetween('sales.sold_at', $this->bounds($period))
            ->orderByDesc('sales.sold_at')
            ->orderByDesc('sales.id')
            ->limit(15)
            ->get([
                'sales.id', 'sales.total', 'sales.payment_method', 'sales.sold_at',
                'users.name as sold_by_name', 'customers.name as customer_name',
            ]);

        $lines = DB::table('sale_items')
            ->leftJoin('items', 'items.id', '=', 'sale_items.item_id')
            ->whereIn('sale_items.sale_id', $sales->pluck('id'))
            ->get(['sale_items.sale_id', 'sale_items.item_type', 'items.name', 'sale_items.qty'])
            ->groupBy('sale_id');

        return $sales->map(fn ($sale) => [
            'id' => $sale->id,
            'total' => (float) $sale->total,
            'payment_method' => $sale->payment_method,
            'sold_at' => $this->toIso($sale->sold_at),
            'sold_by' => $sale->sold_by_name,
            'customer' => $sale->customer_name,
            'summary' => ($lines[$sale->id] ?? collect())
                ->map(fn ($l) => sprintf(
                    '%s× %s',
                    rtrim(rtrim(number_format((float) $l->qty, 2, '.', ''), '0'), '.'),
                    $l->item_type === SaleItem::TYPE_PLATE ? 'Plate' : ($l->name ?? 'Drink'),
                ))
                ->implode(', '),
        ])->values();
    }
}
