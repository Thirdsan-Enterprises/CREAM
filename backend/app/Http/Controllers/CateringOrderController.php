<?php

namespace App\Http\Controllers;

use App\Models\CateringOrder;
use App\Models\CateringPackage;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

class CateringOrderController extends Controller
{
    private const STATUSES = [
        CateringOrder::STATUS_QUOTED,
        CateringOrder::STATUS_CONFIRMED,
        CateringOrder::STATUS_DELIVERED,
        CateringOrder::STATUS_SETTLED,
        CateringOrder::STATUS_CANCELLED,
    ];

    public function index(Request $request)
    {
        $query = CateringOrder::query()->with(['package', 'payments'])->orderByDesc('event_date');

        if ($request->filled('status')) {
            $query->where('status', $request->string('status'));
        }

        if ($request->filled('from')) {
            $query->whereDate('event_date', '>=', $request->date('from'));
        }

        if ($request->filled('to')) {
            $query->whereDate('event_date', '<=', $request->date('to'));
        }

        return $query->paginate()->through(
            fn (CateringOrder $order) => [...$order->toArray(), ...$order->financialSummary()]
        );
    }

    public function show(CateringOrder $cateringOrder)
    {
        $cateringOrder->load(['package', 'payments', 'createdBy']);

        return response()->json([...$cateringOrder->toArray(), ...$cateringOrder->financialSummary()]);
    }

    public function store(Request $request)
    {
        $data = $request->validate([
            'client_name' => ['required', 'string', 'max:255'],
            'client_phone' => ['required', 'string', 'max:50'],
            'event_name' => ['nullable', 'string', 'max:255'],
            'event_date' => ['required', 'date'],
            'catering_package_id' => ['required', 'exists:catering_packages,id'],
            // Defaults to the package's price when omitted — this is the "add
            // a price" override the client asked for on new orders.
            'price_per_plate' => ['nullable', 'numeric', 'min:0'],
            'number_of_plates' => ['required', 'integer', 'min:1'],
            'notes' => ['nullable', 'string', 'max:2000'],
        ]);

        $package = CateringPackage::findOrFail($data['catering_package_id']);
        $pricePerPlate = $data['price_per_plate'] ?? (float) $package->price_per_plate;

        $order = CateringOrder::create([
            ...$data,
            'price_per_plate' => $pricePerPlate,
            'total_amount' => $pricePerPlate * $data['number_of_plates'],
            'status' => CateringOrder::STATUS_QUOTED,
            'created_by' => $request->user()->id,
        ]);

        return response()->json([...$order->load('package')->toArray(), ...$order->financialSummary()], 201);
    }

    public function update(Request $request, CateringOrder $cateringOrder)
    {
        $data = $request->validate([
            'client_name' => ['sometimes', 'string', 'max:255'],
            'client_phone' => ['sometimes', 'string', 'max:50'],
            'event_name' => ['nullable', 'string', 'max:255'],
            'event_date' => ['sometimes', 'date'],
            'catering_package_id' => ['sometimes', 'exists:catering_packages,id'],
            'price_per_plate' => ['sometimes', 'numeric', 'min:0'],
            'number_of_plates' => ['sometimes', 'integer', 'min:1'],
            'notes' => ['nullable', 'string', 'max:2000'],
            'status' => ['sometimes', Rule::in(self::STATUSES)],
        ]);

        $cateringOrder->fill($data);

        if ($cateringOrder->isDirty('catering_package_id') && ! $request->filled('price_per_plate')) {
            $package = CateringPackage::findOrFail($cateringOrder->catering_package_id);
            $cateringOrder->price_per_plate = $package->price_per_plate;
        }

        if ($cateringOrder->isDirty('price_per_plate') || $cateringOrder->isDirty('number_of_plates')) {
            $cateringOrder->total_amount = $cateringOrder->price_per_plate * $cateringOrder->number_of_plates;
        }

        $cateringOrder->save();

        return response()->json([...$cateringOrder->load('package')->toArray(), ...$cateringOrder->financialSummary()]);
    }

    public function addPayment(Request $request, CateringOrder $cateringOrder)
    {
        $data = $request->validate([
            'amount' => ['required', 'numeric', 'gt:0'],
            'payment_method' => ['required', Rule::in(['cash', 'momo', 'airtel', 'bank'])],
            'paid_at' => ['nullable', 'date'],
        ]);

        $payment = $cateringOrder->payments()->create([
            'amount' => $data['amount'],
            'payment_method' => $data['payment_method'],
            'paid_at' => $data['paid_at'] ?? now(),
            'recorded_by' => $request->user()->id,
        ]);

        return response()->json([
            'payment' => $payment,
            'balance_due' => $cateringOrder->balanceDue(),
        ], 201);
    }
}
