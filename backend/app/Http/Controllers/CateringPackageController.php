<?php

namespace App\Http\Controllers;

use App\Models\CateringPackage;
use App\Models\EditLog;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\ValidationException;

class CateringPackageController extends Controller
{
    public function index(Request $request)
    {
        return CateringPackage::query()->orderBy('price_per_plate')->paginate($this->perPage($request, 500));
    }

    public function store(Request $request)
    {
        $data = $request->validate([
            'name' => ['required', 'string', 'max:255'],
            'price_per_plate' => ['required', 'numeric', 'gt:0'],
            'description' => ['nullable', 'string'],
            'is_active' => ['boolean'],
        ]);

        return response()->json(CateringPackage::create($data), 201);
    }

    public function update(Request $request, CateringPackage $cateringPackage)
    {
        $data = $request->validate([
            'name' => ['sometimes', 'string', 'max:255'],
            'price_per_plate' => ['sometimes', 'numeric', 'gt:0'],
            'description' => ['nullable', 'string'],
            'is_active' => ['sometimes', 'boolean'],
            'reason' => ['nullable', 'string', 'max:500'],
        ]);
        $reason = trim($data['reason'] ?? '');
        unset($data['reason']);

        $before = $cateringPackage->only(['name', 'price_per_plate', 'is_active']);
        $cateringPackage->fill($data);
        $changes = EditLog::diff($before, $cateringPackage->only(['name', 'price_per_plate', 'is_active']));

        if (isset($changes['price_per_plate']) && $reason === '') {
            throw ValidationException::withMessages(['reason' => ['Say why the price is changing.']]);
        }

        DB::transaction(function () use ($cateringPackage, $changes, $reason, $request) {
            $cateringPackage->save();
            if ($changes) {
                EditLog::record(
                    $request->user(), 'catering_package', $cateringPackage->id,
                    'Catering package: '.$cateringPackage->name,
                    isset($changes['price_per_plate']) ? 'price_changed' : 'edited',
                    $changes, $reason !== '' ? $reason : 'Details updated', null,
                );
            }
        });

        return $cateringPackage;
    }
}
