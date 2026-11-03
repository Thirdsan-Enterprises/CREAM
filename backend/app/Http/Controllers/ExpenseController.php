<?php

namespace App\Http\Controllers;

use App\Models\EditLog;
use App\Models\Expense;
use App\Models\User;
use App\Support\StoreScope;
use Carbon\CarbonImmutable;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\Rule;
use Illuminate\Validation\ValidationException;

/**
 * Money a branch pays out of its takings: transport for a worker, small
 * items bought on the spot. Recorded by managers, the owner, and anyone the
 * owner allows ("Can record expenses" on their account).
 */
class ExpenseController extends Controller
{
    public function index(Request $request)
    {
        $user = $request->user();
        $storeId = StoreScope::resolve($user, $request->integer('store_id') ?: null);
        $tz = config('app.business_timezone', 'Africa/Kampala');

        $query = Expense::query()->with(['store:id,name', 'recordedBy:id,name', 'voidedBy:id,name'])
            ->latest('spent_at')->latest('id')
            ->when($storeId, fn ($q) => $q->where('store_id', $storeId));
        if ($request->filled('from')) {
            $query->where('spent_at', '>=', CarbonImmutable::parse($request->input('from'), $tz)->startOfDay()->utc());
        }
        if ($request->filled('to')) {
            $query->where('spent_at', '<=', CarbonImmutable::parse($request->input('to'), $tz)->endOfDay()->utc());
        }

        $rows = (clone $query)->get();
        $page = $query->paginate($this->perPage($request));

        return response()->json([
            ...$page->toArray(),
            'total' => (float) $rows->whereNull('voided_at')->sum('amount'),
            'categories' => Expense::CATEGORIES,
        ]);
    }

    public function store(Request $request)
    {
        $user = $request->user();
        if (! $user->canRecordExpenses()) {
            abort(403, 'Ask the owner to allow you to record expenses.');
        }
        $data = $request->validate([
            'store_id' => ['nullable', 'exists:stores,id'],
            'amount' => ['required', 'numeric', 'gt:0', 'max:5000000'],
            'category' => ['required', 'string', 'max:50'],
            'note' => ['required', 'string', 'max:255'],
            'paid_from' => ['nullable', Rule::in(['cash', 'momo', 'airtel'])],
        ], [
            'note.required' => 'Say what the money was for.',
        ]);
        $storeId = StoreScope::resolveRequired($user, $data['store_id'] ?? null);
        StoreScope::assertAccess($user, $storeId);

        $expense = Expense::create([
            'store_id' => $storeId,
            'amount' => $data['amount'],
            'category' => trim($data['category']),
            'note' => trim($data['note']),
            'paid_from' => $data['paid_from'] ?? 'cash',
            'recorded_by' => $user->id,
            'spent_at' => now(),
        ]);

        return response()->json($expense->load(['store:id,name', 'recordedBy:id,name']), 201);
    }

    /** Cancel an expense entered by mistake; kept on record with the reason. */
    public function void(Request $request, Expense $expense)
    {
        $user = $request->user();
        StoreScope::assertAccess($user, $expense->store_id);
        $own = $expense->recorded_by === $user->id && $expense->created_at->gt(now()->subMinutes(15));
        if (! $user->isAdmin() && $user->role !== User::ROLE_STORE_MANAGER && ! $own) {
            abort(403, 'Ask your manager to cancel this expense.');
        }
        $data = $request->validate(['reason' => ['required', 'string', 'max:500']], [
            'reason.required' => 'Say why this expense is being cancelled.',
        ]);
        if ($expense->voided_at) {
            throw ValidationException::withMessages(['expense' => ['This expense was already cancelled.']]);
        }

        DB::transaction(function () use ($expense, $user, $data) {
            $expense->update(['voided_at' => now(), 'voided_by' => $user->id, 'void_reason' => trim($data['reason'])]);
            EditLog::record(
                $user, 'expense', $expense->id, 'Expense: '.$expense->category.' ('.$expense->note.')', 'voided',
                ['amount' => ['from' => (float) $expense->amount, 'to' => 0]], $data['reason'], $expense->store_id,
            );
        });

        return response()->json($expense->fresh()->load(['recordedBy:id,name', 'voidedBy:id,name']));
    }
}
