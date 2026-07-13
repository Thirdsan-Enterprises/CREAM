<?php

namespace Tests\Feature;

use App\Models\Customer;
use App\Models\DrinkPrice;
use App\Models\Item;
use App\Models\PlatePrice;
use App\Models\Store;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class SaleTest extends TestCase
{
    use RefreshDatabase;

    private function seedPlatePrice(): void
    {
        PlatePrice::create([
            'store_id' => null,
            'price' => 25000,
            'effective_from' => now()->toDateString(),
            'is_active' => true,
        ]);
    }

    public function test_cash_sale_with_plate_and_drink_computes_total_and_deducts_drink_stock(): void
    {
        $this->seedPlatePrice();
        $store = Store::factory()->create();
        $soda = Item::factory()->create(['is_drink' => true]);
        DrinkPrice::create([
            'item_id' => $soda->id, 'store_id' => null, 'price' => 3000,
            'effective_from' => now()->toDateString(), 'is_active' => true,
        ]);
        $cashier = User::factory()->create(['role' => User::ROLE_CASHIER, 'store_id' => $store->id]);

        $response = $this->actingAs($cashier)->postJson('/api/sales', [
            'payment_method' => 'cash',
            'lines' => [
                ['item_type' => 'plate', 'qty' => 1],
                ['item_type' => 'drink', 'item_id' => $soda->id, 'qty' => 2],
            ],
        ]);

        $response->assertCreated();
        $this->assertEquals(31000, $response->json('total'));

        $this->assertDatabaseHas('stock_movements', [
            'item_id' => $soda->id, 'store_id' => $store->id, 'type' => 'consumption', 'qty' => -2,
        ]);
    }

    public function test_account_sale_requires_customer_id(): void
    {
        $this->seedPlatePrice();
        $store = Store::factory()->create();
        $cashier = User::factory()->create(['role' => User::ROLE_CASHIER, 'store_id' => $store->id]);

        $response = $this->actingAs($cashier)->postJson('/api/sales', [
            'payment_method' => 'account',
            'lines' => [['item_type' => 'plate', 'qty' => 1]],
        ]);

        $response->assertStatus(422);
    }

    public function test_prepaid_customer_debit_cannot_go_below_zero(): void
    {
        $this->seedPlatePrice();
        $store = Store::factory()->create();
        $cashier = User::factory()->create(['role' => User::ROLE_CASHIER, 'store_id' => $store->id]);
        $customer = Customer::factory()->create(['account_type' => Customer::TYPE_PREPAID]);

        $response = $this->actingAs($cashier)->postJson('/api/sales', [
            'payment_method' => 'account',
            'customer_id' => $customer->id,
            'lines' => [['item_type' => 'plate', 'qty' => 1]],
        ]);

        $response->assertStatus(422);
        $this->assertEquals(0, $customer->fresh()->balance());
        $this->assertDatabaseMissing('sales', ['customer_id' => $customer->id]);
    }

    public function test_credit_customer_debit_within_limit_succeeds_and_over_limit_is_rejected(): void
    {
        $this->seedPlatePrice();
        $store = Store::factory()->create();
        $cashier = User::factory()->create(['role' => User::ROLE_CASHIER, 'store_id' => $store->id]);
        $customer = Customer::factory()->credit(30000)->create();

        $this->actingAs($cashier)->postJson('/api/sales', [
            'payment_method' => 'account',
            'customer_id' => $customer->id,
            'lines' => [['item_type' => 'plate', 'qty' => 1]],
        ])->assertCreated();

        $this->assertEquals(-25000, $customer->fresh()->balance());

        $this->actingAs($cashier)->postJson('/api/sales', [
            'payment_method' => 'account',
            'customer_id' => $customer->id,
            'lines' => [['item_type' => 'plate', 'qty' => 1]],
        ])->assertStatus(422);

        $this->assertEquals(-25000, $customer->fresh()->balance());
    }

    public function test_sales_summary_breaks_out_plate_and_drink_revenue(): void
    {
        $this->seedPlatePrice();
        $store = Store::factory()->create();
        $soda = Item::factory()->create(['is_drink' => true]);
        DrinkPrice::create([
            'item_id' => $soda->id, 'store_id' => null, 'price' => 3000,
            'effective_from' => now()->toDateString(), 'is_active' => true,
        ]);
        $cashier = User::factory()->create(['role' => User::ROLE_CASHIER, 'store_id' => $store->id]);

        $this->actingAs($cashier)->postJson('/api/sales', [
            'payment_method' => 'cash',
            'lines' => [
                ['item_type' => 'plate', 'qty' => 2],
                ['item_type' => 'drink', 'item_id' => $soda->id, 'qty' => 1],
            ],
        ])->assertCreated();

        $response = $this->actingAs($cashier)->getJson('/api/sales/summary');

        $response->assertOk();
        $this->assertEquals(50000, $response->json('plate_revenue'));
        $this->assertEquals(3000, $response->json('drink_revenue'));
        $this->assertEquals(53000, $response->json('total_revenue'));
    }

    public function test_sales_summary_to_date_filter_includes_the_whole_day(): void
    {
        $this->seedPlatePrice();
        $store = Store::factory()->create();
        $cashier = User::factory()->create(['role' => User::ROLE_CASHIER, 'store_id' => $store->id]);

        $this->actingAs($cashier)->postJson('/api/sales', [
            'payment_method' => 'cash',
            'lines' => [['item_type' => 'plate', 'qty' => 1]],
        ])->assertCreated();

        $today = now()->toDateString();
        $response = $this->actingAs($cashier)->getJson("/api/sales/summary?from={$today}&to={$today}");

        $response->assertOk();
        $this->assertEquals(25000, $response->json('total_revenue'));
    }
}
