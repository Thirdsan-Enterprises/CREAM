<?php

namespace App\Http\Controllers;

use App\Models\Customer;
use App\Models\Item;
use App\Models\Sale;
use App\Models\SaleItem;
use App\Models\StockMovement;
use App\Services\LedgerService;
use App\Services\PricingService;
use App\Support\StoreScope;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\Rule;
use Illuminate\Validation\ValidationException;

class SaleController extends Controller
{
    public function __construct(
        private readonly PricingService $pricingService,
        private readonly LedgerService $ledgerService,
    ) {}

    public function index(Request $request)
    {
        $user = $request->user();

        $query = Sale::query()->with(['store', 'soldBy', 'customer', 'items.item'])->orderByDesc('sold_at');

        $storeId = StoreScope::resolve($user, $request->integer('store_id') ?: null);
        if ($storeId !== null) {
            $query->where('store_id', $storeId);
        }

        if ($request->filled('payment_method')) {
            $query->where('payment_method', $request->string('payment_method'));
        }

        if ($request->filled('from')) {
            $query->where('sold_at', '>=', $request->date('from'));
        }

        if ($request->filled('to')) {
            $query->where('sold_at', '<=', $request->date('to')->endOfDay());
        }

        return $query->paginate();
    }

    public function store(Request $request)
    {
        $user = $request->user();

        $data = $request->validate([
            'store_id' => ['nullable', 'exists:stores,id'],
            'payment_method' => ['required', Rule::in([
                Sale::PAYMENT_CASH, Sale::PAYMENT_MOMO, Sale::PAYMENT_AIRTEL, Sale::PAYMENT_ACCOUNT,
            ])],
            'customer_id' => ['nullable', 'exists:customers,id', 'required_if:payment_method,'.Sale::PAYMENT_ACCOUNT],
            'lines' => ['required', 'array', 'min:1'],
            'lines.*.item_type' => ['required', Rule::in([SaleItem::TYPE_PLATE, SaleItem::TYPE_DRINK])],
            'lines.*.item_id' => ['nullable', 'required_if:lines.*.item_type,'.SaleItem::TYPE_DRINK, 'exists:items,id'],
            'lines.*.qty' => ['required', 'numeric', 'gt:0'],
        ]);

        $storeId = StoreScope::resolveRequired($user, $data['store_id'] ?? null);
        StoreScope::assertAccess($user, $storeId);

        $customer = null;
        if ($data['payment_method'] === Sale::PAYMENT_ACCOUNT) {
            $customer = Customer::findOrFail($data['customer_id']);
        }

        $sale = DB::transaction(function () use ($data, $storeId, $user, $customer) {
            $lineInputs = [];
            $total = 0;

            foreach ($data['lines'] as $line) {
                if ($line['item_type'] === SaleItem::TYPE_PLATE) {
                    $unitPrice = $this->pricingService->currentPlatePrice($storeId);
                    $itemId = null;
                } else {
                    $item = Item::findOrFail($line['item_id']);
                    if (! $item->is_drink) {
                        throw ValidationException::withMessages([
                            'lines' => ["Item {$item->name} is not a drink."],
                        ]);
                    }
                    $unitPrice = $this->pricingService->currentDrinkPrice($item->id, $storeId);
                    if ($unitPrice === null) {
                        throw ValidationException::withMessages([
                            'lines' => ["No price is set for {$item->name}."],
                        ]);
                    }
                    $itemId = $item->id;
                }

                $lineTotal = round($unitPrice * $line['qty'], 2);
                $total += $lineTotal;

                $lineInputs[] = [
                    'item_type' => $line['item_type'],
                    'item_id' => $itemId,
                    'qty' => $line['qty'],
                    'unit_price' => $unitPrice,
                    'line_total' => $lineTotal,
                ];
            }

            $sale = Sale::create([
                'store_id' => $storeId,
                'sold_by' => $user->id,
                'payment_method' => $data['payment_method'],
                'customer_id' => $customer?->id,
                'total' => $total,
                'sold_at' => now(),
            ]);

            foreach ($lineInputs as $lineInput) {
                $sale->items()->create($lineInput);

                if ($lineInput['item_type'] === SaleItem::TYPE_DRINK) {
                    StockMovement::create([
                        'item_id' => $lineInput['item_id'],
                        'store_id' => $storeId,
                        'type' => StockMovement::TYPE_CONSUMPTION,
                        'qty' => -abs($lineInput['qty']),
                        'user_id' => $user->id,
                        'occurred_at' => now(),
                    ]);
                }
            }

            if ($customer) {
                $this->ledgerService->debit($customer, $total, $sale->id, $user->id, 'Sale #'.$sale->id);
            }

            return $sale;
        });

        return response()->json($sale->load('items.item'), 201);
    }

    public function summary(Request $request)
    {
        $user = $request->user();

        $query = Sale::query()->with('items');

        $storeId = StoreScope::resolve($user, $request->integer('store_id') ?: null);
        if ($storeId !== null) {
            $query->where('store_id', $storeId);
        }

        if ($request->filled('from')) {
            $query->where('sold_at', '>=', $request->date('from'));
        }

        if ($request->filled('to')) {
            $query->where('sold_at', '<=', $request->date('to')->endOfDay());
        }

        $sales = $query->get();

        $plateRevenue = 0;
        $drinkRevenue = 0;
        $plateCount = 0;
        $byPaymentMethod = [];

        foreach ($sales as $sale) {
            $byPaymentMethod[$sale->payment_method] = ($byPaymentMethod[$sale->payment_method] ?? 0) + (float) $sale->total;

            foreach ($sale->items as $item) {
                if ($item->item_type === SaleItem::TYPE_PLATE) {
                    $plateRevenue += (float) $item->line_total;
                    $plateCount += (float) $item->qty;
                } else {
                    $drinkRevenue += (float) $item->line_total;
                }
            }
        }

        return response()->json([
            'store_id' => $storeId,
            'sales_count' => $sales->count(),
            'total_revenue' => $plateRevenue + $drinkRevenue,
            'plate_revenue' => $plateRevenue,
            'drink_revenue' => $drinkRevenue,
            'plates_sold' => $plateCount,
            'by_payment_method' => (object) $byPaymentMethod,
        ]);
    }
}
