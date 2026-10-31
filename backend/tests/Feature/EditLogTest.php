<?php

namespace Tests\Feature;

use App\Models\CateringOrder;
use App\Models\CateringPackage;
use App\Models\Customer;
use App\Models\DrinkPrice;
use App\Models\EditLog;
use App\Models\Item;
use App\Models\ItemStoreSetting;
use App\Models\PlatePrice;
use App\Models\StockMovement;
use App\Models\Store;
use App\Models\User;
use App\Services\LedgerService;
use App\Services\StockService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * Changing anything already entered says what changed and why, and the
 * owner can read it back.
 */
class EditLogTest extends TestCase
{
    use RefreshDatabase;

    private User $owner;

    private User $manager;

    private User $cashier;

    private Store $town;

    private Item $soda;

    protected function setUp(): void
    {
        parent::setUp();
        $this->owner = User::factory()->create(['role' => User::ROLE_ADMIN, 'store_id' => null]);
        Store::factory()->create(['name' => 'Kira', 'is_main' => true]);
        $this->town = Store::factory()->create(['name' => 'Town']);
        $this->manager = User::factory()->create(['role' => User::ROLE_STORE_MANAGER, 'store_id' => $this->town->id]);
        $this->cashier = User::factory()->create(['role' => User::ROLE_CASHIER, 'store_id' => $this->town->id]);
        PlatePrice::create(['store_id' => null, 'price' => 25000, 'effective_from' => now()->toDateString(), 'is_active' => true]);

        $this->soda = Item::factory()->create(['name' => 'Soda', 'is_drink' => true, 'is_sellable' => true, 'sell_category' => 'Drinks', 'tracks_stock' => true]);
        ItemStoreSetting::create(['item_id' => $this->soda->id, 'store_id' => $this->town->id, 'safety_stock' => 0]);
        DrinkPrice::create(['item_id' => $this->soda->id, 'store_id' => null, 'price' => 2000, 'effective_from' => now()->toDateString(), 'is_active' => true]);
        StockMovement::create(['item_id' => $this->soda->id, 'store_id' => $this->town->id, 'type' => 'purchase', 'qty' => 10, 'user_id' => $this->owner->id, 'occurred_at' => now()]);
    }

    private function sell(array $extra = []): int
    {
        return $this->actingAs($this->cashier)->postJson('/api/sales', [
            'payment_method' => 'cash',
            'lines' => [
                ['item_type' => 'plate', 'qty' => 1],
                ['item_type' => 'drink', 'item_id' => $this->soda->id, 'qty' => 2],
            ],
            ...$extra,
        ])->assertCreated()->json('id');
    }

    public function test_a_voided_sale_returns_stock_and_leaves_the_totals(): void
    {
        $saleId = $this->sell();
        $stock = app(StockService::class);
        $this->assertEquals(8, $stock->balance($this->soda->id, $this->town->id));

        $this->actingAs($this->manager)->postJson("/api/sales/{$saleId}/void", ['reason' => 'Rang up twice'])
            ->assertOk()
            ->assertJsonPath('void_reason', 'Rang up twice')
            ->assertJsonPath('voided_by.name', $this->manager->name);

        $this->assertEquals(10, $stock->balance($this->soda->id, $this->town->id), 'sodas back on the shelf');

        $summary = $this->actingAs($this->owner)->getJson('/api/sales/summary?store_id='.$this->town->id)->json();
        $this->assertEquals(0, $summary['total_revenue']);
        $this->assertEquals(0, $summary['sales_count']);
        $branches = $this->actingAs($this->owner)->getJson('/api/reports/branches?range=today')->json('branches');
        $this->assertEquals(0, collect($branches)->firstWhere('store_name', 'Town')['revenue']);

        // Still listed, marked as voided.
        $this->actingAs($this->owner)->getJson('/api/sales')->assertJsonPath('data.0.void_reason', 'Rang up twice');

        $log = EditLog::sole();
        $this->assertSame('voided', $log->action);
        $this->assertSame("Sale #{$saleId}", $log->subject_label);
        $this->assertSame($this->manager->id, $log->user_id);
    }

    public function test_voiding_an_account_sale_credits_the_customer_back(): void
    {
        $customer = Customer::factory()->create(['account_type' => Customer::TYPE_PREPAID]);
        app(LedgerService::class)->deposit($customer, 50000, $this->owner->id);
        $saleId = $this->sell(['payment_method' => 'account', 'customer_id' => $customer->id]);
        $this->assertEquals(21000, $customer->balance());

        $this->actingAs($this->owner)->postJson("/api/sales/{$saleId}/void", ['reason' => 'Wrong customer'])->assertOk();
        $this->assertEquals(50000, $customer->balance());
    }

    public function test_a_sale_can_only_be_voided_once_with_a_reason_by_a_manager_of_that_branch(): void
    {
        $saleId = $this->sell();

        $this->actingAs($this->cashier)->postJson("/api/sales/{$saleId}/void", ['reason' => 'Oops'])->assertForbidden();
        $this->actingAs($this->manager)->postJson("/api/sales/{$saleId}/void", [])
            ->assertUnprocessable()->assertJsonPath('errors.reason.0', 'Say why this sale is being voided.');

        $otherBranch = Store::factory()->create(['name' => 'Lugogo']);
        $otherManager = User::factory()->create(['role' => User::ROLE_STORE_MANAGER, 'store_id' => $otherBranch->id]);
        $this->actingAs($otherManager)->postJson("/api/sales/{$saleId}/void", ['reason' => 'Not mine'])->assertForbidden();

        $this->actingAs($this->manager)->postJson("/api/sales/{$saleId}/void", ['reason' => 'Double'])->assertOk();
        $this->actingAs($this->owner)->postJson("/api/sales/{$saleId}/void", ['reason' => 'Again'])->assertUnprocessable();
        $this->assertEquals(10, app(StockService::class)->balance($this->soda->id, $this->town->id), 'stock returned once only');
    }

    public function test_a_stock_correction_is_logged_with_the_balance_before_and_after(): void
    {
        $this->actingAs($this->manager)->postJson('/api/stock/adjustment', [
            'item_id' => $this->soda->id, 'qty' => -2, 'note' => 'Two bottles broke',
        ])->assertCreated();

        $log = EditLog::sole();
        $this->assertSame('stock_corrected', $log->action);
        $this->assertSame('Soda at Town', $log->subject_label);
        $this->assertEquals(['balance' => ['from' => 10, 'to' => 8]], $log->changes);
        $this->assertSame('Two bottles broke', $log->reason);
    }

    public function test_changing_an_agreed_catering_order_needs_a_reason(): void
    {
        $package = CateringPackage::factory()->create(['price_per_plate' => 34000]);
        $order = CateringOrder::factory()->create([
            'catering_package_id' => $package->id, 'price_per_plate' => 34000, 'number_of_plates' => 100,
            'total_amount' => 3400000, 'status' => 'confirmed', 'created_by' => $this->owner->id,
        ]);

        $this->actingAs($this->owner)->patchJson("/api/catering-orders/{$order->id}", ['number_of_plates' => 120])
            ->assertUnprocessable()->assertJsonPath('errors.reason.0', 'Say why this order is being changed.');

        $this->actingAs($this->owner)->patchJson("/api/catering-orders/{$order->id}", [
            'number_of_plates' => 120, 'reason' => 'Client added guests',
        ])->assertOk()->assertJsonPath('total_amount', 4080000);

        $log = EditLog::sole();
        $this->assertSame('edited', $log->action);
        $this->assertEquals(100, $log->changes['number_of_plates']['from']);
        $this->assertEquals(120, $log->changes['number_of_plates']['to']);
        $this->assertArrayHasKey('total_amount', $log->changes);

        // Moving the order along needs no reason, but is still recorded.
        $this->actingAs($this->owner)->patchJson("/api/catering-orders/{$order->id}", ['status' => 'delivered'])->assertOk();
        $this->assertSame('status_changed', EditLog::latest('id')->first()->action);
    }
}
