<?php

namespace App\Http\Controllers;

use App\Models\ItemStoreSetting;
use App\Models\Store;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

class StoreController extends Controller
{
    public function index(Request $request)
    {
        return Store::query()->orderBy('name')->paginate($this->perPage($request, 500));
    }

    public function store(Request $request)
    {
        $data = $request->validate([
            'name' => ['required', 'string', 'max:255'],
            'code' => ['required', 'string', 'max:50', 'unique:stores,code'],
            'is_main' => ['boolean'],
            'address' => ['nullable', 'string'],
            'phone' => ['nullable', 'string'],
            'is_active' => ['boolean'],
        ]);

        $store = DB::transaction(function () use ($data) {
            $store = Store::create($data);
            ItemStoreSetting::backfillForStore($store);

            return $store;
        });

        return response()->json($store, 201);
    }

    public function update(Request $request, Store $store)
    {
        $data = $request->validate([
            'name' => ['sometimes', 'string', 'max:255'],
            'code' => ['sometimes', 'string', 'max:50', 'unique:stores,code,'.$store->id],
            'is_main' => ['sometimes', 'boolean'],
            'address' => ['nullable', 'string'],
            'phone' => ['nullable', 'string'],
            'is_active' => ['sometimes', 'boolean'],
        ]);

        $store->update($data);

        return $store;
    }
}
