<?php

namespace App\Http\Controllers;

use App\Models\CateringPackage;
use Illuminate\Http\Request;

class CateringPackageController extends Controller
{
    public function index()
    {
        return CateringPackage::query()->orderBy('price_per_plate')->paginate();
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
        ]);

        $cateringPackage->update($data);

        return $cateringPackage;
    }
}
