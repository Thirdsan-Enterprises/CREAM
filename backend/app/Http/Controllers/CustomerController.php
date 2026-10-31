<?php

namespace App\Http\Controllers;

use App\Models\Customer;
use App\Models\EditLog;
use App\Models\LedgerEntry;
use App\Models\Store;
use App\Services\CustomerStanding;
use App\Services\LedgerService;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\Rule;

/**
 * Customer accounts. Each branch has its own customers: staff see and add
 * customers of their branch (plus older accounts with no branch); the owner
 * sees every branch and can filter by one.
 */
class CustomerController extends Controller
{
    public function __construct(
        private readonly LedgerService $ledgerService,
        private readonly CustomerStanding $standing,
    ) {}

    public function index(Request $request)
    {
        $user = $request->user();

        // withSum(... as balance) computes each customer's ledger balance in
        // the same query (one extra subquery total, not N+1) so the list can
        // show it directly without a follow-up call per customer.
        $query = Customer::query()
            ->with('store:id,name')
            ->withSum('ledgerEntries as balance', 'amount')
            ->orderBy('name');

        if ($user->isAdmin()) {
            if ($request->filled('store_id')) {
                $query->where('store_id', $request->integer('store_id'));
            }
        } else {
            $query->where(fn ($q) => $q->where('store_id', $user->store_id)->orWhereNull('store_id'));
        }

        if ($request->filled('search')) {
            $search = $request->string('search');
            $query->where(function ($q) use ($search) {
                $q->where('name', 'like', "%{$search}%")
                    ->orWhere('phone', 'like', "%{$search}%");
            });
        }

        if ($request->filled('account_type')) {
            $query->where('account_type', $request->string('account_type'));
        }

        $page = $query->paginate($this->perPage($request, 500));
        $page->getCollection()->transform(fn (Customer $customer) => $this->withStanding($customer, (float) $customer->balance));

        // ?attention=1: only accounts near or at their limit.
        if ($request->boolean('attention')) {
            $page->setCollection($page->getCollection()->filter(fn ($c) => $c['status'] !== 'ok')->values());
        }

        return $page;
    }

    public function show(Request $request, Customer $customer)
    {
        $this->authorizeCustomer($request, $customer);

        return response()->json($this->withStanding($customer->load('store:id,name')));
    }

    public function store(Request $request)
    {
        $user = $request->user();
        $data = $request->validate([
            'name' => ['required', 'string', 'max:255'],
            'phone' => ['required', 'string', 'unique:customers,phone'],
            'account_type' => ['required', Rule::in([Customer::TYPE_PREPAID, Customer::TYPE_CREDIT, Customer::TYPE_LPO])],
            'credit_limit' => ['nullable', 'numeric', 'min:0'],
            'store_id' => ['nullable', 'exists:stores,id'],
        ], [
            'phone.unique' => 'A customer with this phone number already exists.',
        ]);

        // Staff always add customers to their own branch. Credit is the
        // owner's decision: staff open credit accounts with no limit until
        // the owner sets one.
        $storeId = $user->isAdmin() ? ($data['store_id'] ?? null) : $user->store_id;
        $limit = $user->isAdmin() ? ($data['credit_limit'] ?? 0) : 0;

        $customer = Customer::create([
            ...$data,
            'store_id' => $storeId,
            'credit_limit' => $limit,
            'is_active' => true,
            'created_by' => $user->id,
        ]);

        return response()->json($this->withStanding($customer->load('store:id,name'), 0), 201);
    }

    /**
     * Change a customer's details. A reason is required and the change is
     * logged. Only the owner sets credit limits, account types and branches.
     */
    public function update(Request $request, Customer $customer)
    {
        $user = $request->user();
        $this->authorizeCustomer($request, $customer);

        $data = $request->validate([
            'name' => ['sometimes', 'string', 'max:255'],
            'phone' => ['sometimes', 'string', Rule::unique('customers', 'phone')->ignore($customer->id)],
            'is_active' => ['sometimes', 'boolean'],
            'credit_limit' => ['sometimes', 'numeric', 'min:0'],
            'account_type' => ['sometimes', Rule::in([Customer::TYPE_PREPAID, Customer::TYPE_CREDIT, Customer::TYPE_LPO])],
            'store_id' => ['sometimes', 'nullable', 'exists:stores,id'],
            'reason' => ['required', 'string', 'max:500'],
        ], [
            'reason.required' => 'Say why this account is changing.',
            'phone.unique' => 'A customer with this phone number already exists.',
        ]);

        $ownerOnly = array_intersect(array_keys($data), ['credit_limit', 'account_type', 'store_id']);
        if ($ownerOnly && ! $user->isAdmin()) {
            abort(403, 'Only the owner can change credit limits, account types or branches.');
        }

        $fields = ['name', 'phone', 'is_active', 'credit_limit', 'account_type', 'store_id'];
        $before = $customer->only($fields);
        $customer->fill(array_intersect_key($data, array_flip($fields)));
        $changes = EditLog::diff($before, $customer->only($fields));

        if (isset($changes['store_id'])) {
            $names = Store::whereIn('id', array_filter([$changes['store_id']['from'], $changes['store_id']['to']]))->pluck('name', 'id');
            $changes['store_id'] = [
                'from' => $names[$changes['store_id']['from']] ?? 'All branches',
                'to' => $names[$changes['store_id']['to']] ?? 'All branches',
            ];
        }

        DB::transaction(function () use ($customer, $changes, $data, $user) {
            $customer->save();
            if ($changes) {
                EditLog::record($user, 'customer', $customer->id, 'Customer: '.$customer->name, 'edited', $changes, $data['reason'], $customer->store_id);
            }
        });

        return response()->json($this->withStanding($customer->fresh()->load('store:id,name')));
    }

    public function statement(Request $request, Customer $customer)
    {
        $this->authorizeCustomer($request, $customer);

        return response()->json([
            'customer' => $customer->load('store:id,name'),
            'balance' => $customer->balance(),
            'standing' => $this->standing->for($customer),
            'entries' => $customer->ledgerEntries()->with('recordedBy:id,name')->orderByDesc('occurred_at')->orderByDesc('id')->paginate($this->perPage($request)),
        ]);
    }

    public function balance(Request $request, Customer $customer)
    {
        $this->authorizeCustomer($request, $customer);

        return response()->json([
            'customer_id' => $customer->id,
            ...$this->standing->for($customer),
        ]);
    }

    public function deposit(Request $request, Customer $customer)
    {
        $this->authorizeCustomer($request, $customer);

        $data = $request->validate([
            'amount' => ['required', 'numeric', 'gt:0'],
            'note' => ['nullable', 'string'],
        ]);

        $entry = $this->ledgerService->deposit($customer, $data['amount'], $request->user()->id, $data['note'] ?? null);

        return response()->json([
            'entry' => $entry,
            ...$this->standing->for($customer),
        ], 201);
    }

    /**
     * Correct an account: a deposit entered twice, a wrong amount. Positive
     * adds to the balance, negative takes away. Logged with the reason.
     */
    public function adjust(Request $request, Customer $customer)
    {
        $this->authorizeCustomer($request, $customer);

        $data = $request->validate([
            'amount' => ['required', 'numeric', 'not_in:0'],
            'reason' => ['required', 'string', 'max:500'],
        ], [
            'reason.required' => 'Say why this account is being corrected.',
        ]);

        $user = $request->user();
        $entry = DB::transaction(function () use ($customer, $data, $user) {
            $before = $customer->balance();
            $entry = LedgerEntry::create([
                'customer_id' => $customer->id,
                'type' => LedgerEntry::TYPE_ADJUSTMENT,
                'amount' => $data['amount'],
                'note' => 'Correction: '.trim($data['reason']),
                'recorded_by' => $user->id,
                'occurred_at' => now(),
            ]);
            EditLog::record(
                $user, 'customer', $customer->id, 'Customer: '.$customer->name, 'balance_corrected',
                ['balance' => ['from' => $before, 'to' => $before + (float) $data['amount']]],
                $data['reason'], $customer->store_id,
            );

            return $entry;
        });

        return response()->json([
            'entry' => $entry,
            ...$this->standing->for($customer),
        ], 201);
    }

    private function authorizeCustomer(Request $request, Customer $customer): void
    {
        if (! $customer->isServedBy($request->user())) {
            abort(403, 'This customer belongs to another branch.');
        }
    }

    private function withStanding(Customer $customer, ?float $balance = null): array
    {
        return [...$customer->toArray(), ...$this->standing->for($customer, $balance)];
    }
}
