<?php

namespace App\Http\Controllers;

use App\Models\Customer;
use App\Models\Item;
use App\Models\ItemStoreSetting;
use App\Models\Sale;
use App\Models\SaleItem;
use App\Models\StockMovement;
use App\Models\Store;
use App\Services\LedgerService;
use App\Services\PricingService;
use App\Services\StockService;
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
        private readonly StockService $stockService,
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

        return $query->paginate($this->perPage($request));
    }

    public function store(Request $request)
    {
        $user = $request->user();

        $data = $request->validate([
            'store_id' => ['nullable', 'exists:stores,id'],
            'payment_method' => ['required', Rule::in([
                Sale::PAYMENT_CASH, Sale::PAYMENT_MOMO, Sale::PAYMENT_AIRTEL, Sale::PAYMENT_ACCOUNT, Sale::PAYMENT_LPO,
            ])],
            'customer_id' => ['nullable', 'exists:customers,id', 'required_if:payment_method,'.Sale::PAYMENT_ACCOUNT],
            'lines' => ['required', 'array', 'min:1'],
            // 'drink' is what apps sent before any item could be sold; it
            // means the same as 'item'.
            'lines.*.item_type' => ['required', Rule::in([SaleItem::TYPE_PLATE, SaleItem::TYPE_DRINK, SaleItem::TYPE_ITEM])],
            'lines.*.item_id' => ['nullable', 'required_unless:lines.*.item_type,'.SaleItem::TYPE_PLATE, 'exists:items,id'],
            'lines.*.qty' => ['required', 'numeric', 'min:0'],
        ]);

        // A customer can buy a drink or an egg without a plate. The Sell
        // screen sends "0 plates" in that case, so lines with nothing on them
        // are dropped rather than refused.
        $data['lines'] = array_values(array_filter($data['lines'], fn ($line) => (float) $line['qty'] > 0));
        if ($data['lines'] === []) {
            throw ValidationException::withMessages([
                'lines' => ['Add at least one plate or item to the sale.'],
            ]);
        }

        $storeId = StoreScope::resolveRequired($user, $data['store_id'] ?? null);
        StoreScope::assertAccess($user, $storeId);

        $customer = null;
        if ($data['payment_method'] === Sale::PAYMENT_ACCOUNT) {
            $customer = Customer::findOrFail($data['customer_id']);
        }

        $sale = DB::transaction(function () use ($data, $storeId, $user, $customer) {
            $this->assertItemsInStock($data['lines'], $storeId);

            $lineInputs = [];
            $total = 0;

            foreach ($data['lines'] as $line) {
                if ($line['item_type'] === SaleItem::TYPE_PLATE) {
                    $unitPrice = $this->pricingService->currentPlatePrice($storeId);
                    $itemId = null;
                } else {
                    $item = Item::findOrFail($line['item_id']);
                    if (! $item->is_sellable && ! $item->is_drink) {
                        throw ValidationException::withMessages([
                            'lines' => ["{$item->name} is not on the menu."],
                        ]);
                    }
                    $unitPrice = $this->pricingService->currentItemPrice($item->id, $storeId);
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
                    'item_type' => $line['item_type'] === SaleItem::TYPE_PLATE
                        ? SaleItem::TYPE_PLATE
                        : ($item->is_drink ? SaleItem::TYPE_DRINK : SaleItem::TYPE_ITEM),
                    'tracks_stock' => $line['item_type'] !== SaleItem::TYPE_PLATE && $item->tracks_stock,
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
                $tracksStock = $lineInput['tracks_stock'];
                unset($lineInput['tracks_stock']);
                $sale->items()->create($lineInput);

                if ($tracksStock) {
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

    /**
     * An item that tracks stock (every drink, an egg) can only be sold if
     * the branch has it. The branch's stock balance is the single record of
     * what is on the shelf, so a sale that would take it below zero is
     * refused with a message that says what to do. An item may be on
     * several lines, so they are added up first. Items made to order from
     * other stock (a cup of tea) do not track stock and are never limited.
     */
    private function assertItemsInStock(array $lines, int $storeId): void
    {
        $wanted = [];
        foreach ($lines as $line) {
            if ($line['item_type'] !== SaleItem::TYPE_PLATE) {
                $wanted[$line['item_id']] = ($wanted[$line['item_id']] ?? 0) + (float) $line['qty'];
            }
        }
        $items = Item::whereIn('id', array_keys($wanted))->get();
        // Kitchen stock (rice, oil) is not sold over the counter: say so
        // before talking about how much of it is left.
        foreach ($items as $item) {
            if (! $item->is_sellable && ! $item->is_drink) {
                throw ValidationException::withMessages([
                    'lines' => ["{$item->name} is not on the menu."],
                ]);
            }
        }
        $tracked = $items->where('tracks_stock', true)->pluck('id')->all();
        $wanted = array_intersect_key($wanted, array_flip($tracked));

        foreach ($wanted as $itemId => $qty) {
            // Serialise sales of the same drink at the same branch, so two
            // cashiers cannot both sell the last bottle.
            ItemStoreSetting::query()
                ->where('item_id', $itemId)->where('store_id', $storeId)
                ->lockForUpdate()->first();

            $available = $this->stockService->balance($itemId, $storeId);
            if ($qty > $available) {
                $item = Item::find($itemId);
                $left = max($available, 0);
                $branch = Store::find($storeId)?->name;
                throw ValidationException::withMessages([
                    'lines' => ["Only {$left} {$item?->name} in stock at {$branch}: cannot sell {$qty}. Record the purchase first."],
                ]);
            }
        }
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
        $itemRevenue = 0;
        $plateCount = 0;
        $drinkCount = 0;
        $itemCount = 0;
        $byPaymentMethod = [];

        foreach ($sales as $sale) {
            $byPaymentMethod[$sale->payment_method] = ($byPaymentMethod[$sale->payment_method] ?? 0) + (float) $sale->total;

            foreach ($sale->items as $item) {
                if ($item->item_type === SaleItem::TYPE_PLATE) {
                    $plateRevenue += (float) $item->line_total;
                    $plateCount += (float) $item->qty;
                } elseif ($item->item_type === SaleItem::TYPE_DRINK) {
                    $drinkRevenue += (float) $item->line_total;
                    $drinkCount += (float) $item->qty;
                } else {
                    $itemRevenue += (float) $item->line_total;
                    $itemCount += (float) $item->qty;
                }
            }
        }

        return response()->json([
            'store_id' => $storeId,
            'sales_count' => $sales->count(),
            'total_revenue' => $plateRevenue + $drinkRevenue + $itemRevenue,
            'plate_revenue' => $plateRevenue,
            'drink_revenue' => $drinkRevenue,
            // Everything sold on its own that is not a drink: eggs, tea...
            'item_revenue' => $itemRevenue,
            'plates_sold' => $plateCount,
            'drinks_sold' => $drinkCount,
            'items_sold' => $itemCount,
            'by_payment_method' => (object) $byPaymentMethod,
        ]);
    }
}
