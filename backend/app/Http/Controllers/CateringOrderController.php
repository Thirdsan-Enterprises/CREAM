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

        return $query->paginate();
    }

    public function show(CateringOrder $cateringOrder)
    {
        return $cateringOrder->load(['package', 'payments', 'createdBy']);
    }

    public function store(Request $request)
    {
        $data = $request->validate([
            'client_name' => ['required', 'string', 'max:255'],
            'client_phone' => ['required', 'string', 'max:50'],
            'event_name' => ['nullable', 'string', 'max:255'],
            'event_date' => ['required', 'date'],
            'catering_package_id' => ['required', 'exists:catering_packages,id'],
            'number_of_plates' => ['required', 'integer', 'min:1'],
        ]);

        $package = CateringPackage::findOrFail($data['catering_package_id']);

        $order = CateringOrder::create([
            ...$data,
            'total_amount' => $package->price_per_plate * $data['number_of_plates'],
            'status' => CateringOrder::STATUS_QUOTED,
            'created_by' => $request->user()->id,
        ]);

        return response()->json($order->load('package'), 201);
    }

    public function update(Request $request, CateringOrder $cateringOrder)
    {
        $data = $request->validate([
            'client_name' => ['sometimes', 'string', 'max:255'],
            'client_phone' => ['sometimes', 'string', 'max:50'],
            'event_name' => ['nullable', 'string', 'max:255'],
            'event_date' => ['sometimes', 'date'],
            'catering_package_id' => ['sometimes', 'exists:catering_packages,id'],
            'number_of_plates' => ['sometimes', 'integer', 'min:1'],
            'status' => ['sometimes', Rule::in(self::STATUSES)],
        ]);

        $cateringOrder->fill($data);

        if ($cateringOrder->isDirty('catering_package_id') || $cateringOrder->isDirty('number_of_plates')) {
            $package = CateringPackage::findOrFail($cateringOrder->catering_package_id);
            $cateringOrder->total_amount = $package->price_per_plate * $cateringOrder->number_of_plates;
        }

        $cateringOrder->save();

        return $cateringOrder->load('package');
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
