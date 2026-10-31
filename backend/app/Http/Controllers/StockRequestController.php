<?php

namespace App\Http\Controllers;

use App\Models\StockRequest;
use App\Models\Store;
use App\Models\User;
use App\Services\StockService;
use App\Services\TransferService;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\ValidationException;

/**
 * Branches tell the procurement unit what they are missing. Procurement
 * answers each request by sending the items (a normal transfer the branch
 * confirms on arrival) or declining it with a reason.
 */
class StockRequestController extends Controller
{
    public function __construct(
        private readonly TransferService $transferService,
        private readonly StockService $stockService,
    ) {}

    /** Procurement and the owner see every branch's requests; a branch its own. */
    public function index(Request $request)
    {
        $user = $request->user();
        $query = StockRequest::query()
            ->with(['store:id,name', 'requestedBy:id,name', 'respondedBy:id,name', 'items.item:id,name,unit', 'transfer:id,status'])
            ->orderByRaw("CASE WHEN status = 'open' THEN 0 ELSE 1 END")
            ->latest()->latest('id');

        if (! $this->seesAll($user)) {
            $query->where('store_id', $user->store_id);
        } elseif ($request->filled('store_id')) {
            $query->where('store_id', $request->integer('store_id'));
        }
        if ($request->filled('status')) {
            $query->where('status', $request->string('status'));
        }

        $page = $query->paginate($this->perPage($request));

        // Procurement needs to know what it has on hand for each line.
        $main = Store::main();
        if ($main && $this->seesAll($user)) {
            $page->getCollection()->each(function (StockRequest $req) use ($main) {
                if ($req->status === StockRequest::STATUS_OPEN) {
                    $req->items->each(fn ($line) => $line->setAttribute(
                        'available_at_procurement',
                        $this->stockService->balance($line->item_id, $main->id),
                    ));
                }
            });
        }

        return $page;
    }

    public function show(Request $request, StockRequest $stockRequest)
    {
        $this->assertVisible($request->user(), $stockRequest);

        return $stockRequest->load(['store:id,name', 'requestedBy:id,name', 'respondedBy:id,name', 'items.item:id,name,unit', 'transfer']);
    }

    /** A branch asks for items. */
    public function store(Request $request)
    {
        $user = $request->user();
        $data = $request->validate([
            'store_id' => ['nullable', 'exists:stores,id'],
            'items' => ['required', 'array', 'min:1'],
            'items.*.item_id' => ['required', 'distinct', 'exists:items,id'],
            'items.*.qty' => ['required', 'numeric', 'gt:0'],
            'note' => ['nullable', 'string', 'max:1000'],
        ], [
            'items.*.item_id.distinct' => 'Each item can only be listed once.',
        ]);

        $storeId = $user->isAdmin() ? ($data['store_id'] ?? null) : $user->store_id;
        if (! $storeId) {
            throw ValidationException::withMessages(['store_id' => ['Choose the branch that needs the items.']]);
        }
        if (Store::find($storeId)?->is_main) {
            throw ValidationException::withMessages(['store_id' => ['The procurement unit buys its own stock: record a purchase instead.']]);
        }

        $stockRequest = DB::transaction(function () use ($data, $storeId, $user) {
            $stockRequest = StockRequest::create([
                'store_id' => $storeId,
                'requested_by' => $user->id,
                'status' => StockRequest::STATUS_OPEN,
                'note' => $data['note'] ?? null,
            ]);
            foreach ($data['items'] as $line) {
                $stockRequest->items()->create(['item_id' => $line['item_id'], 'qty_requested' => $line['qty']]);
            }

            return $stockRequest;
        });

        return response()->json($stockRequest->load(['store:id,name', 'items.item:id,name,unit']), 201);
    }

    /**
     * Procurement sends what was asked for (or less, or none of some lines).
     * The quantities go out as one transfer from the main store.
     */
    public function send(Request $request, StockRequest $stockRequest)
    {
        $user = $request->user();
        $this->assertProcurement($user);
        $this->assertOpen($stockRequest);

        $data = $request->validate([
            'items' => ['nullable', 'array'],
            'items.*.stock_request_item_id' => ['required', 'exists:stock_request_items,id'],
            'items.*.qty' => ['required', 'numeric', 'min:0'],
            'note' => ['nullable', 'string', 'max:1000'],
        ]);

        $main = Store::main() ?? abort(422, 'Set the procurement unit in Settings first.');

        // Default: send exactly what was asked for.
        $qtys = $stockRequest->items->mapWithKeys(fn ($line) => [$line->id => (float) $line->qty_requested])->all();
        foreach ($data['items'] ?? [] as $line) {
            if (! array_key_exists($line['stock_request_item_id'], $qtys)) {
                throw ValidationException::withMessages(['items' => ['That line is not part of this request.']]);
            }
            $qtys[$line['stock_request_item_id']] = (float) $line['qty'];
        }

        $lines = [];
        foreach ($stockRequest->items as $line) {
            if ($qtys[$line->id] > 0) {
                $lines[] = ['item_id' => $line->item_id, 'qty' => $qtys[$line->id]];
            }
        }
        if ($lines === []) {
            throw ValidationException::withMessages(['items' => ['Nothing to send. Decline the request instead, with a reason.']]);
        }

        DB::transaction(function () use ($stockRequest, $user, $main, $lines, $qtys, $data) {
            $transfer = $this->transferService->dispatch($user, $main, $stockRequest->store_id, $lines);

            foreach ($stockRequest->items as $line) {
                $line->update(['qty_sent' => $qtys[$line->id]]);
            }
            $stockRequest->update([
                'status' => StockRequest::STATUS_SENT,
                'responded_by' => $user->id,
                'responded_at' => now(),
                'response_note' => $data['note'] ?? null,
                'stock_transfer_id' => $transfer->id,
            ]);
        });

        return response()->json($stockRequest->fresh()->load(['store:id,name', 'items.item:id,name,unit', 'transfer', 'respondedBy:id,name']));
    }

    /** Procurement cannot help (not in stock, not needed): says why. */
    public function decline(Request $request, StockRequest $stockRequest)
    {
        $user = $request->user();
        $this->assertProcurement($user);
        $this->assertOpen($stockRequest);

        $data = $request->validate(['reason' => ['required', 'string', 'max:1000']], [
            'reason.required' => 'Tell the branch why.',
        ]);

        $stockRequest->update([
            'status' => StockRequest::STATUS_DECLINED,
            'responded_by' => $user->id,
            'responded_at' => now(),
            'response_note' => trim($data['reason']),
        ]);

        return response()->json($stockRequest->fresh()->load(['store:id,name', 'items.item:id,name,unit', 'respondedBy:id,name']));
    }

    /** The branch no longer needs it. */
    public function cancel(Request $request, StockRequest $stockRequest)
    {
        $user = $request->user();
        if (! $user->isAdmin() && $user->store_id !== $stockRequest->store_id) {
            abort(403, 'Only the branch that asked can cancel this request.');
        }
        $this->assertOpen($stockRequest);

        $stockRequest->update([
            'status' => StockRequest::STATUS_CANCELLED,
            'responded_by' => $user->id,
            'responded_at' => now(),
        ]);

        return response()->json($stockRequest->fresh());
    }

    private function seesAll(User $user): bool
    {
        return $user->isAdmin() || $user->isProcurement();
    }

    private function assertVisible(User $user, StockRequest $stockRequest): void
    {
        if (! $this->seesAll($user) && $user->store_id !== $stockRequest->store_id) {
            abort(403, 'This request belongs to another branch.');
        }
    }

    private function assertProcurement(User $user): void
    {
        if (! $user->isAdmin() && ! $user->isProcurement()) {
            abort(403, 'Only the procurement unit can answer requests.');
        }
    }

    private function assertOpen(StockRequest $stockRequest): void
    {
        if ($stockRequest->status !== StockRequest::STATUS_OPEN) {
            throw ValidationException::withMessages(['status' => ["This request was already {$stockRequest->status}."]]);
        }
    }
}
