<?php

namespace App\Http\Controllers;

use App\Models\Customer;
use App\Models\EditLog;
use App\Models\Item;
use App\Models\ItemStoreSetting;
use App\Models\LedgerEntry;
use App\Models\Sale;
use App\Models\SaleItem;
use App\Models\StockMovement;
use App\Models\Store;
use App\Models\User;
use App\Services\CustomerStanding;
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

        $query = Sale::query()->with(['store', 'soldBy', 'customer', 'items.item', 'voidedBy:id,name'])->orderByDesc('sold_at');

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
            'customer_id' => ['nullable', 'exists:customers,id', 'required_if:payment_method,'.Sale::PAYMENT_ACCOUNT.','.Sale::PAYMENT_LPO],
            'lines' => ['required', 'array', 'min:1'],
            // 'drink' is what apps sent before any item could be sold; it
            // means the same as 'item'.
            'lines.*.item_type' => ['required', Rule::in([SaleItem::TYPE_PLATE, SaleItem::TYPE_DRINK, SaleItem::TYPE_ITEM])],
            'lines.*.item_id' => ['nullable', 'required_unless:lines.*.item_type,'.SaleItem::TYPE_PLATE, 'exists:items,id'],
            'lines.*.qty' => ['required', 'numeric', 'min:0'],
            // A discount off the whole sale, always with a note saying why.
            'discount' => ['nullable', 'numeric', 'min:0'],
            'discount_note' => ['nullable', 'string', 'max:255'],
        ]);
        $discount = round((float) ($data['discount'] ?? 0), 2);
        if ($discount > 0 && trim((string) ($data['discount_note'] ?? '')) === '') {
            throw ValidationException::withMessages(['discount_note' => ['Say why there is a discount.']]);
        }

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
        $store = Store::findOrFail($storeId);
        if (! $store->sells) {
            throw ValidationException::withMessages([
                'store_id' => ["{$store->name} is the procurement unit and does not sell. Choose a branch."],
            ]);
        }

        $customer = null;
        $lpo = null;
        if (in_array($data['payment_method'], [Sale::PAYMENT_ACCOUNT, Sale::PAYMENT_LPO], true)) {
            $customer = Customer::findOrFail($data['customer_id']);
            if ($customer->store_id !== null && $customer->store_id !== $storeId) {
                $home = $customer->store?->name ?? 'another branch';
                throw ValidationException::withMessages([
                    'customer_id' => ["{$customer->name} is a customer of {$home}. Charge their account at {$home}, or ask the owner to move it."],
                ]);
            }
            if (! $customer->is_active) {
                throw ValidationException::withMessages([
                    'customer_id' => ["{$customer->name}'s account is closed."],
                ]);
            }
            // LPO customers are charged by LPO, and only they are.
            if ($customer->account_type === Customer::TYPE_LPO) {
                $data['payment_method'] = Sale::PAYMENT_LPO;
                $lpo = $customer->currentLpo() ?? throw ValidationException::withMessages([
                    'customer_id' => ["{$customer->name} has no LPO yet. Record the LPO on their account first."],
                ]);
            } elseif ($data['payment_method'] === Sale::PAYMENT_LPO) {
                throw ValidationException::withMessages([
                    'customer_id' => ["{$customer->name} is not an LPO account. Choose Account to charge them."],
                ]);
            }
        }

        $sale = DB::transaction(function () use ($data, $storeId, $user, $customer, $discount, $lpo) {
            $this->assertItemsInStock($data['lines'], $storeId);

            $lineInputs = [];
            $total = 0;

            foreach ($data['lines'] as $line) {
                if ($line['item_type'] === SaleItem::TYPE_PLATE) {
                    $unitPrice = $this->pricingService->currentPlatePrice($storeId);
                    $itemId = null;
                    $item = null;
                } else {
                    $item = Item::findOrFail($line['item_id']);
                    if (! $item->is_sellable && ! $item->is_drink) {
                        throw ValidationException::withMessages([
                            'lines' => ["{$item->name} is not on the menu."],
                        ]);
                    }
                    $offMenu = ItemStoreSetting::where('item_id', $item->id)->where('store_id', $storeId)
                        ->where('on_menu', false)->exists();
                    if ($offMenu) {
                        $branch = Store::find($storeId)?->name;
                        throw ValidationException::withMessages([
                            'lines' => ["{$item->name} is not on the menu at {$branch}."],
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
                    // A lunch (Beef, Fish...) is a plate: it counts in plates
                    // sold and plate revenue, and names the dish.
                    'item_type' => $line['item_type'] === SaleItem::TYPE_PLATE || self::isLunch($item ?? null)
                        ? SaleItem::TYPE_PLATE
                        : ($item->is_drink ? SaleItem::TYPE_DRINK : SaleItem::TYPE_ITEM),
                    'tracks_stock' => $line['item_type'] !== SaleItem::TYPE_PLATE && $item->tracks_stock,
                    'item_id' => $itemId,
                    'qty' => $line['qty'],
                    'unit_price' => $unitPrice,
                    'line_total' => $lineTotal,
                ];
            }

            if ($lpo) {
                $this->assertLpoCovers($lpo, $lineInputs);
            }

            if ($discount >= $total) {
                throw ValidationException::withMessages(['discount' => ['The discount must be less than the sale ('.number_format($total).').']]);
            }

            $sale = Sale::create([
                'store_id' => $storeId,
                'sold_by' => $user->id,
                'payment_method' => $data['payment_method'],
                'customer_id' => $customer?->id,
                'customer_lpo_id' => $lpo?->id,
                'total' => $total - $discount,
                'discount' => $discount,
                'discount_note' => $discount > 0 ? trim($data['discount_note']) : null,
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
                        'note' => 'Sale #'.$sale->id,
                        'user_id' => $user->id,
                        'occurred_at' => now(),
                    ]);
                }
            }

            if ($customer) {
                // What the customer pays: after any discount.
                $this->ledgerService->debit($customer, $total - $discount, $sale->id, $user->id,
                    'Sale #'.$sale->id.($lpo ? ' on LPO '.($lpo->number ?: '#'.$lpo->id) : ''));
            }

            return $sale;
        });

        $body = $sale->load('items.item')->toArray();
        if ($customer) {
            // Tell the cashier straight away if this account is getting low.
            $body['customer_account'] = app(CustomerStanding::class)->for($customer->fresh());
        }

        return response()->json($body, 201);
    }

    /** Dishes under the Lunch heading are plates. */
    /**
     * An LPO pays only for what it covers (lunch, breakfast, drinks) and
     * for no more lunch plates than it includes. Packing for takeaway is
     * always allowed.
     */
    private function assertLpoCovers(\App\Models\CustomerLpo $lpo, array $lines): void
    {
        $label = 'LPO '.($lpo->number ?: '#'.$lpo->id);
        $plates = 0;
        foreach ($lines as $line) {
            $item = $line['item_id'] ? Item::find($line['item_id']) : null;
            $heading = $line['item_type'] === SaleItem::TYPE_PLATE
                ? 'Lunch'
                : ($item->sell_category ?: ($item->is_drink ? 'Drinks' : 'Other'));
            if ($line['item_type'] === SaleItem::TYPE_PLATE) {
                $plates += $line['qty'];
            }
            if (strcasecmp($heading, 'Packing') === 0 || $lpo->covers($heading)) {
                continue;
            }
            $what = $item?->name ?? 'Plate';
            throw ValidationException::withMessages(['lines' => [
                "{$label} does not cover {$heading} ({$what}). Take payment for it separately.",
            ]]);
        }
        if ($lpo->plates !== null && $plates > 0) {
            $left = $lpo->plates - $lpo->platesUsed();
            if ($plates > $left) {
                throw ValidationException::withMessages(['lines' => [
                    $left <= 0
                        ? "{$label} has no plates left (all {$lpo->plates} used)."
                        : "{$label} has only {$left} plates left: cannot charge {$plates}.",
                ]]);
            }
        }
    }

    public static function isLunch(?Item $item): bool
    {
        return $item !== null && strcasecmp((string) $item->sell_category, 'Lunch') === 0;
    }

    /**
     * Void a sale entered by mistake. The sale stays on record, marked with
     * who voided it and why; what it took from stock goes back on the
     * shelf and an account charge is credited back, in one transaction.
     * The owner can void any sale, a store manager only at their branch.
     */
    /** How long a cashier may still cancel a sale they made. */
    public const CASHIER_CANCEL_MINUTES = 15;

    public function void(Request $request, Sale $sale)
    {
        $user = $request->user();
        StoreScope::assertAccess($user, $sale->store_id);
        // A cashier may cancel their own sale shortly after making it (a
        // mistake, or the customer changed their mind); after that, or for
        // someone else's sale, the manager or owner does it.
        if ($user->role === User::ROLE_CASHIER) {
            $recent = $sale->sold_by === $user->id
                && $sale->sold_at->gt(now()->subMinutes(self::CASHIER_CANCEL_MINUTES));
            if (! $recent) {
                abort(403, 'Only a sale you made in the last '.self::CASHIER_CANCEL_MINUTES.' minutes can be cancelled. Ask your manager.');
            }
        }

        $data = $request->validate([
            'reason' => ['required', 'string', 'max:500'],
        ], [
            'reason.required' => 'Say why this sale is being voided.',
        ]);

        DB::transaction(function () use ($sale, $user, $data) {
            $sale = Sale::whereKey($sale->id)->lockForUpdate()->firstOrFail();
            if ($sale->isVoided()) {
                throw ValidationException::withMessages(['sale' => ["Sale #{$sale->id} was already voided."]]);
            }

            $note = "Sale #{$sale->id} voided: ".trim($data['reason']);

            $returned = StockMovement::where('type', StockMovement::TYPE_CONSUMPTION)
                ->where('store_id', $sale->store_id)
                ->where('note', 'Sale #'.$sale->id)
                ->get(['item_id', 'qty'])
                ->map(fn ($m) => ['item_id' => $m->item_id, 'qty' => abs((float) $m->qty)]);
            if ($returned->isEmpty()) {
                // Sales recorded before stock movements named their sale:
                // fall back to the lines of items that count stock.
                $returned = $sale->items()->whereNotNull('item_id')
                    ->whereHas('item', fn ($q) => $q->where('tracks_stock', true))
                    ->get(['item_id', 'qty'])
                    ->map(fn ($l) => ['item_id' => $l->item_id, 'qty' => (float) $l->qty]);
            }
            foreach ($returned as $movement) {
                StockMovement::create([
                    'item_id' => $movement['item_id'],
                    'store_id' => $sale->store_id,
                    'type' => StockMovement::TYPE_ADJUSTMENT,
                    'qty' => $movement['qty'],
                    'note' => $note,
                    'user_id' => $user->id,
                    'occurred_at' => now(),
                ]);
            }

            if ($sale->customer_id) {
                LedgerEntry::create([
                    'customer_id' => $sale->customer_id,
                    'type' => LedgerEntry::TYPE_ADJUSTMENT,
                    'amount' => (float) $sale->total,
                    'related_sale_id' => $sale->id,
                    'note' => $note,
                    'recorded_by' => $user->id,
                    'occurred_at' => now(),
                ]);
            }

            $sale->update([
                'voided_at' => now(),
                'voided_by' => $user->id,
                'void_reason' => trim($data['reason']),
            ]);

            EditLog::record(
                $user, 'sale', $sale->id, "Sale #{$sale->id}", 'voided',
                [
                    'total' => ['from' => (float) $sale->total, 'to' => 0],
                    'payment_method' => ['from' => $sale->payment_method, 'to' => $sale->payment_method],
                ],
                $data['reason'], $sale->store_id,
            );
        });

        return response()->json($sale->fresh()->load(['items.item', 'voidedBy:id,name']));
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
            $offMenu = ItemStoreSetting::where('item_id', $item->id)->where('store_id', $storeId)
                ->where('on_menu', false)->exists();
            if ($offMenu) {
                $branch = Store::find($storeId)?->name;
                throw ValidationException::withMessages([
                    'lines' => ["{$item->name} is not on the menu at {$branch}."],
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
                $message = $item?->daily_stock
                    ? ($left <= 0
                        ? "No {$item->name} plates left today at {$branch}. Add today's plates first."
                        : "Only {$left} {$item->name} plates left today at {$branch}: cannot sell {$qty}.")
                    : "Only {$left} {$item?->name} in stock at {$branch}: cannot sell {$qty}. Record the purchase first.";
                throw ValidationException::withMessages(['lines' => [$message]]);
            }
        }
    }

    public function summary(Request $request)
    {
        $user = $request->user();

        $query = Sale::query()->counted()->with('items');

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
            // What was taken: everything sold less discounts given.
            'total_revenue' => $plateRevenue + $drinkRevenue + $itemRevenue - (float) $sales->sum('discount'),
            'discounts' => (float) $sales->sum('discount'),
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
