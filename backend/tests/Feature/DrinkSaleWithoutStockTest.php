<?php

namespace Tests\Feature;

use App\Models\DrinkPrice;
use App\Models\Item;
use App\Models\ItemStoreSetting;
use App\Models\PlatePrice;
use App\Models\Store;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * The user manual tells staff that a drink can still be sold when the
 * system shows none in stock, and that the balance then goes below zero
 * until the purchase is recorded. If that rule changes, change the manual.
 */
class DrinkSaleWithoutStockTest extends TestCase
{
    use RefreshDatabase;

    public function test_a_drink_can_be_sold_with_no_stock_recorded_and_the_balance_goes_negative(): void
    {
        $store = Store::factory()->create();
        $cashier = User::factory()->create(['role' => User::ROLE_CASHIER, 'store_id' => $store->id]);
        $water = Item::factory()->create(['name' => 'Water', 'is_drink' => true]);
        ItemStoreSetting::create(['item_id' => $water->id, 'store_id' => $store->id, 'safety_stock' => 10]);
        DrinkPrice::create([
            'item_id' => $water->id, 'store_id' => null, 'price' => 2000,
            'effective_from' => now()->toDateString(), 'is_active' => true,
        ]);
        PlatePrice::create(['store_id' => null, 'price' => 25000, 'effective_from' => now()->toDateString(), 'is_active' => true]);

        $this->actingAs($cashier)->postJson('/api/sales', [
            'payment_method' => 'cash',
            'lines' => [['item_type' => 'drink', 'item_id' => $water->id, 'qty' => 3]],
        ])->assertCreated();

        $row = collect($this->actingAs($cashier)->getJson('/api/stock/status')->json('items'))
            ->firstWhere('item_name', 'Water');

        $this->assertEquals(-3, $row['balance']);
        $this->assertSame('Re-Order', $row['status']);
    }
}
