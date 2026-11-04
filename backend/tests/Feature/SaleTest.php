<?php

namespace Tests\Feature;

use App\Models\Customer;
use App\Models\DrinkPrice;
use App\Models\Item;
use App\Models\PlatePrice;
use App\Models\StockMovement;
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
        StockMovement::create([
            'item_id' => $soda->id, 'store_id' => $store->id, 'type' => StockMovement::TYPE_PURCHASE,
            'qty' => 10, 'user_id' => $cashier->id, 'occurred_at' => now(),
        ]);

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

    private function lpoCustomer(User $by, array $lpo): Customer
    {
        $id = $this->actingAs($by)->postJson('/api/customers', [
            'name' => 'Acme Ltd', 'phone' => '07'.random_int(10000000, 99999999), 'account_type' => 'lpo', 'lpo' => $lpo,
        ])->assertCreated()->json('id');

        return Customer::findOrFail($id);
    }

    public function test_an_lpo_sale_is_charged_to_the_customers_lpo_and_stops_at_its_amount(): void
    {
        $this->seedPlatePrice();
        $store = Store::factory()->create();
        $cashier = User::factory()->create(['role' => User::ROLE_CASHIER, 'store_id' => $store->id]);
        $customer = $this->lpoCustomer($cashier, ['number' => 'LPO-0042', 'amount' => 25000, 'covers' => ['Lunch']]);

        // LPO needs the customer it is charged to.
        $this->actingAs($cashier)->postJson('/api/sales', [
            'payment_method' => 'lpo',
            'lines' => [['item_type' => 'plate', 'qty' => 1]],
        ])->assertUnprocessable()->assertJsonValidationErrors('customer_id');

        $sale = $this->actingAs($cashier)->postJson('/api/sales', [
            'payment_method' => 'lpo',
            'customer_id' => $customer->id,
            'lines' => [['item_type' => 'plate', 'qty' => 1]],
        ])->assertCreated()->assertJsonPath('payment_method', 'lpo');
        $this->assertEquals(0, $customer->fresh()->balance());
        $this->assertNotNull($sale->json('customer_lpo_id'));

        // "Account" for an LPO customer is charged as LPO too.
        $this->actingAs($cashier)->postJson('/api/sales', [
            'payment_method' => 'account',
            'customer_id' => $customer->id,
            'lines' => [['item_type' => 'plate', 'qty' => 1]],
        ])->assertStatus(422)->assertJsonFragment(['This customer does not have sufficient LPO balance remaining.']);
    }

    public function test_an_lpo_covers_only_what_it_says_and_no_more_plates_than_it_includes(): void
    {
        $this->seedPlatePrice();
        $store = Store::factory()->create();
        $cashier = User::factory()->create(['role' => User::ROLE_CASHIER, 'store_id' => $store->id]);
        $customer = $this->lpoCustomer($cashier, ['number' => 'LPO-7', 'amount' => 1000000, 'plates' => 3, 'covers' => ['Lunch']]);
        $soda = Item::factory()->create(['name' => 'Soda', 'is_drink' => true, 'is_sellable' => true, 'sell_category' => 'Drinks', 'tracks_stock' => false]);
        \App\Models\DrinkPrice::create(['item_id' => $soda->id, 'price' => 2000, 'effective_from' => now()->toDateString(), 'is_active' => true]);

        $charge = fn (array $lines) => $this->actingAs($cashier)->postJson('/api/sales', [
            'payment_method' => 'lpo', 'customer_id' => $customer->id, 'lines' => $lines,
        ]);

        $charge([['item_type' => 'plate', 'qty' => 1], ['item_type' => 'item', 'item_id' => $soda->id, 'qty' => 1]])
            ->assertUnprocessable()->assertJsonFragment(['LPO LPO-7 does not cover Drinks (Soda). Take payment for it separately.']);

        $charge([['item_type' => 'plate', 'qty' => 2]])->assertCreated();
        $charge([['item_type' => 'plate', 'qty' => 2]])
            ->assertUnprocessable()->assertJsonFragment(['LPO LPO-7 has only 1 plates left: cannot charge 2.']);

        $standing = $this->actingAs($cashier)->getJson("/api/customers/{$customer->id}/balance")->json();
        $this->assertSame(1, $standing['lpo']['plates_left']);
        $this->assertSame('low', $standing['status']);

        // The next LPO: sales go on it, and what was left carries on.
        $this->actingAs($cashier)->postJson("/api/customers/{$customer->id}/lpos", [
            'number' => 'LPO-8', 'amount' => 500000, 'plates' => 20, 'covers' => ['Lunch', 'Drinks'],
        ])->assertCreated()->assertJsonPath('lpo.plates_left', 20);
        $charge([['item_type' => 'plate', 'qty' => 2], ['item_type' => 'item', 'item_id' => $soda->id, 'qty' => 2]])->assertCreated();
        $this->assertCount(2, $this->actingAs($cashier)->getJson("/api/customers/{$customer->id}/lpos")->json('data'));
        $this->assertEquals(1000000 - 50000 + 500000 - 54000, $customer->fresh()->balance());
    }

    public function test_the_owner_corrects_an_lpo_and_it_is_logged(): void
    {
        $this->seedPlatePrice();
        $store = Store::factory()->create();
        $cashier = User::factory()->create(['role' => User::ROLE_CASHIER, 'store_id' => $store->id]);
        $owner = User::factory()->create(['role' => User::ROLE_ADMIN, 'store_id' => null]);
        $customer = $this->lpoCustomer($cashier, ['number' => 'LPO-9', 'amount' => 100000, 'plates' => 4, 'covers' => ['Lunch']]);
        $lpo = $customer->currentLpo();
        $this->actingAs($cashier)->postJson('/api/sales', [
            'payment_method' => 'lpo', 'customer_id' => $customer->id, 'lines' => [['item_type' => 'plate', 'qty' => 2]],
        ])->assertCreated();

        $url = "/api/customers/{$customer->id}/lpos/{$lpo->id}";
        $this->actingAs($cashier)->patchJson($url, ['covers' => ['Lunch', 'Drinks'], 'reason' => 'x'])->assertForbidden();
        $this->actingAs($owner)->patchJson($url, ['covers' => ['Lunch', 'Drinks']])->assertUnprocessable()->assertJsonValidationErrors('reason');
        $this->actingAs($owner)->patchJson($url, ['plates' => 1, 'reason' => 'typo'])
            ->assertUnprocessable()->assertJsonFragment(['2 plates are already charged to LPO LPO-9.']);

        $this->actingAs($owner)->patchJson($url, [
            'number' => 'LPO-9A', 'amount' => 150000, 'plates' => 6, 'covers' => ['Lunch', 'Breakfast', 'Drinks'], 'reason' => 'Drinks forgotten',
        ])->assertOk()
            ->assertJsonPath('lpo.plates_left', 4)
            ->assertJsonPath('lpo.covers', ['Lunch', 'Breakfast', 'Drinks'])
            ->assertJsonPath('balance', 150000 - 50000);

        $log = \App\Models\EditLog::latest('id')->first();
        $this->assertSame('lpo_edited', $log->action);
        $this->assertSame('Lunch, Breakfast, Drinks', $log->changes['covers']['to']);
    }

    public function test_a_discount_comes_off_what_the_account_is_charged(): void
    {
        $this->seedPlatePrice();
        $store = Store::factory()->create();
        $cashier = User::factory()->create(['role' => User::ROLE_CASHIER, 'store_id' => $store->id]);
        $customer = Customer::factory()->create(['account_type' => Customer::TYPE_PREPAID]);
        $this->actingAs($cashier)->postJson("/api/customers/{$customer->id}/deposit", ['amount' => 50000])->assertCreated();

        $this->actingAs($cashier)->postJson('/api/sales', [
            'payment_method' => 'account', 'customer_id' => $customer->id,
            'lines' => [['item_type' => 'plate', 'qty' => 1]],
            'discount' => 5000, 'discount_note' => 'Regular',
        ])->assertCreated();
        $this->assertEquals(30000, $customer->fresh()->balance());
    }

    public function test_prepaid_customer_can_deposit_upfront_and_draw_down_across_multiple_days(): void
    {
        // Mirrors the client's real "office lunch tab" scenario: someone pays
        // upfront for a batch of plates, then a variable number of people eat
        // against that balance day to day until it runs out.
        $this->seedPlatePrice();
        $store = Store::factory()->create();
        $cashier = User::factory()->create(['role' => User::ROLE_CASHIER, 'store_id' => $store->id]);
        $customer = Customer::factory()->create(['account_type' => Customer::TYPE_PREPAID]);

        // Deposit enough for 50 plates at 25,000 each.
        $this->actingAs($cashier)->postJson("/api/customers/{$customer->id}/deposit", [
            'amount' => 50 * 25000,
        ])->assertCreated();
        $this->assertEquals(1_250_000, $customer->fresh()->balance());

        // Day 1: 3 people eat.
        $this->actingAs($cashier)->postJson('/api/sales', [
            'payment_method' => 'account',
            'customer_id' => $customer->id,
            'lines' => [['item_type' => 'plate', 'qty' => 3]],
        ])->assertCreated();
        $this->assertEquals(1_175_000, $customer->fresh()->balance());

        // Day 2: 7 people eat.
        $this->actingAs($cashier)->postJson('/api/sales', [
            'payment_method' => 'account',
            'customer_id' => $customer->id,
            'lines' => [['item_type' => 'plate', 'qty' => 7]],
        ])->assertCreated();
        $this->assertEquals(1_000_000, $customer->fresh()->balance());

        // Drain the rest of the balance (40 more plates = 1,000,000).
        $this->actingAs($cashier)->postJson('/api/sales', [
            'payment_method' => 'account',
            'customer_id' => $customer->id,
            'lines' => [['item_type' => 'plate', 'qty' => 40]],
        ])->assertCreated();
        $this->assertEquals(0, $customer->fresh()->balance());

        // The 51st plate has no balance behind it and must be rejected —
        // and rejected atomically, so no partial sale/ledger row is left behind.
        $this->actingAs($cashier)->postJson('/api/sales', [
            'payment_method' => 'account',
            'customer_id' => $customer->id,
            'lines' => [['item_type' => 'plate', 'qty' => 1]],
        ])->assertStatus(422);
        $this->assertEquals(0, $customer->fresh()->balance());
        $this->assertEquals(3, $customer->fresh()->ledgerEntries()->where('type', 'sale_debit')->count());

        // Topping up resumes eating against the account exactly as before.
        $this->actingAs($cashier)->postJson("/api/customers/{$customer->id}/deposit", [
            'amount' => 5 * 25000,
        ])->assertCreated();
        $this->actingAs($cashier)->postJson('/api/sales', [
            'payment_method' => 'account',
            'customer_id' => $customer->id,
            'lines' => [['item_type' => 'plate', 'qty' => 1]],
        ])->assertCreated();
        $this->assertEquals(100000, $customer->fresh()->balance());
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
        StockMovement::create([
            'item_id' => $soda->id, 'store_id' => $store->id, 'type' => StockMovement::TYPE_PURCHASE,
            'qty' => 10, 'user_id' => $cashier->id, 'occurred_at' => now(),
        ]);

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
