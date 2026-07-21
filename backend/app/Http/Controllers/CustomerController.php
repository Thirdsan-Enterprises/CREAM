<?php

namespace App\Http\Controllers;

use App\Models\Customer;
use App\Services\LedgerService;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

class CustomerController extends Controller
{
    public function __construct(private readonly LedgerService $ledgerService) {}

    public function index(Request $request)
    {
        // withSum(... as balance) computes each customer's ledger balance in
        // the same query (one extra subquery total, not N+1) so the list can
        // show it directly without a follow-up call per customer.
        $query = Customer::query()->withSum('ledgerEntries as balance', 'amount')->orderBy('name');

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

        return $query->paginate();
    }

    public function show(Customer $customer)
    {
        return $customer;
    }

    public function store(Request $request)
    {
        $data = $request->validate([
            'name' => ['required', 'string', 'max:255'],
            'phone' => ['required', 'string', 'unique:customers,phone'],
            'account_type' => ['required', Rule::in([Customer::TYPE_PREPAID, Customer::TYPE_CREDIT])],
            'credit_limit' => ['nullable', 'numeric', 'min:0'],
        ]);

        $customer = Customer::create([
            ...$data,
            'credit_limit' => $data['credit_limit'] ?? 0,
            'is_active' => true,
            'created_by' => $request->user()->id,
        ]);

        return response()->json($customer, 201);
    }

    public function statement(Customer $customer)
    {
        return response()->json([
            'customer' => $customer,
            'balance' => $customer->balance(),
            'entries' => $customer->ledgerEntries()->orderByDesc('occurred_at')->paginate(),
        ]);
    }

    public function balance(Customer $customer)
    {
        return response()->json([
            'customer_id' => $customer->id,
            'balance' => $customer->balance(),
        ]);
    }

    public function deposit(Request $request, Customer $customer)
    {
        $data = $request->validate([
            'amount' => ['required', 'numeric', 'gt:0'],
            'note' => ['nullable', 'string'],
        ]);

        $entry = $this->ledgerService->deposit($customer, $data['amount'], $request->user()->id, $data['note'] ?? null);

        return response()->json([
            'entry' => $entry,
            'balance' => $customer->balance(),
        ], 201);
    }
}
