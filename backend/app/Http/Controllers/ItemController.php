<?php

namespace App\Http\Controllers;

use App\Models\Item;
use App\Models\ItemStoreSetting;
use App\Services\StockService;
use Illuminate\Http\Request;

class ItemController extends Controller
{
    public function __construct(private readonly StockService $stockService) {}

    public function index(Request $request)
    {
        $query = Item::query()->orderBy('name');

        if ($request->boolean('is_drink', false) && $request->has('is_drink')) {
            $query->where('is_drink', $request->boolean('is_drink'));
        }

        if ($request->has('is_active')) {
            $query->where('is_active', $request->boolean('is_active'));
        }

        return $query->paginate();
    }

    public function store(Request $request)
    {
        $data = $request->validate([
            'name' => ['required', 'string', 'max:255'],
            'unit' => ['required', 'string', 'max:50'],
            'category' => ['nullable', 'string', 'max:100'],
            'is_drink' => ['boolean'],
            'is_active' => ['boolean'],
        ]);

        return response()->json(Item::create($data), 201);
    }

    public function update(Request $request, Item $item)
    {
        $data = $request->validate([
            'name' => ['sometimes', 'string', 'max:255'],
            'unit' => ['sometimes', 'string', 'max:50'],
            'category' => ['nullable', 'string', 'max:100'],
            'is_drink' => ['sometimes', 'boolean'],
            'is_active' => ['sometimes', 'boolean'],
        ]);

        $item->update($data);

        return $item;
    }

    public function balances(Item $item)
    {
        return response()->json([
            'item' => $item,
            'balances' => $this->stockService->balances($item->id),
        ]);
    }

    public function setStoreSettings(Request $request, Item $item)
    {
        $data = $request->validate([
            'store_id' => ['required', 'exists:stores,id'],
            'safety_stock' => ['required', 'numeric', 'min:0'],
        ]);

        $setting = ItemStoreSetting::updateOrCreate(
            ['item_id' => $item->id, 'store_id' => $data['store_id']],
            ['safety_stock' => $data['safety_stock']],
        );

        return response()->json($setting, 200);
    }
}
