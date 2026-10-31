<?php

namespace App\Http\Controllers;

use App\Models\ItemStoreSetting;
use App\Models\Store;
use App\Models\User;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\ValidationException;

class StoreController extends Controller
{
    public function index(Request $request)
    {
        return Store::query()->orderByDesc('is_main')->orderBy('name')->paginate($this->perPage($request, 500));
    }

    public function store(Request $request)
    {
        $data = $request->validate([
            'name' => ['required', 'string', 'max:255'],
            'code' => ['required', 'string', 'max:50', 'unique:stores,code'],
            'is_main' => ['boolean'],
            'sells' => ['boolean'],
            'address' => ['nullable', 'string'],
            'phone' => ['nullable', 'string'],
            'is_active' => ['boolean'],
        ]);

        $store = DB::transaction(function () use ($data) {
            if (! empty($data['is_main'])) {
                Store::where('is_main', true)->update(['is_main' => false]);
            }
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
            'sells' => ['sometimes', 'boolean'],
            'address' => ['nullable', 'string'],
            'phone' => ['nullable', 'string'],
            'is_active' => ['sometimes', 'boolean'],
        ]);

        if (array_key_exists('is_main', $data) && ! $data['is_main'] && $store->is_main) {
            throw ValidationException::withMessages([
                'is_main' => ['There must be a procurement unit: make another branch the procurement unit instead.'],
            ]);
        }

        DB::transaction(function () use ($store, $data) {
            // Only one procurement unit: choosing a new one hands the role
            // over, together with the procurement staff.
            if (! empty($data['is_main']) && ! $store->is_main) {
                $old = Store::main();
                Store::where('is_main', true)->update(['is_main' => false]);
                if ($old) {
                    User::where('role', User::ROLE_STOREKEEPER)->where('store_id', $old->id)->update(['store_id' => $store->id]);
                }
            }
            $store->update($data);
        });

        return $store->fresh();
    }
}
