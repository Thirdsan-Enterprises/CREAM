<?php

namespace Tests\Feature;

use App\Models\Item;
use App\Models\ItemStoreSetting;
use App\Models\Sale;
use App\Models\SaleItem;
use App\Models\StockMovement;
use App\Models\StockTransfer;
use App\Models\Store;
use App\Models\User;
use Carbon\Carbon;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class BranchReportTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();

        config(['app.business_timezone' => 'Africa/Kampala']);
        // 2 Oct 2026, 12:00 in Kampala (UTC+3).
        Carbon::setTestNow(Carbon::parse('2026-10-02 09:00:00', 'UTC'));
    }

    protected function tearDown(): void
    {
        Carbon::setTestNow();
        parent::tearDown();
    }

    private function sale(Store $store, User $seller, string $utc, int $plates, array $drinks = [], string $method = 'cash'): Sale
    {
        $total = $plates * 25000;
        foreach ($drinks as [$item, $qty, $price]) {
            $total += $qty * $price;
        }

        $sale = Sale::create([
            'store_id' => $store->id, 'sold_by' => $seller->id, 'payment_method' => $method,
            'total' => $total, 'sold_at' => Carbon::parse($utc, 'UTC'),
        ]);

        if ($plates > 0) {
            SaleItem::create([
                'sale_id' => $sale->id, 'item_type' => 'plate', 'qty' => $plates,
                'unit_price' => 25000, 'line_total' => $plates * 25000,
            ]);
        }

        foreach ($drinks as [$item, $qty, $price]) {
            SaleItem::create([
                'sale_id' => $sale->id, 'item_type' => 'drink', 'item_id' => $item->id, 'qty' => $qty,
                'unit_price' => $price, 'line_total' => $qty * $price,
            ]);
        }

        return $sale;
    }

    public function test_overview_breaks_revenue_down_by_branch_and_compares_with_the_previous_period(): void
    {
        $admin = User::factory()->create(['role' => User::ROLE_ADMIN, 'store_id' => null]);
        $kira = Store::factory()->create(['name' => 'Kira', 'is_main' => true]);
        $town = Store::factory()->create(['name' => 'Town']);
        $soda = Item::factory()->create(['name' => 'Soda', 'is_drink' => true]);

        // Today (Kampala): Kira 3 plates + 2 sodas, Town 1 plate on MoMo.
        $this->sale($kira, $admin, '2026-10-02 07:30:00', 3, [[$soda, 2, 2000]]);
        $this->sale($town, $admin, '2026-10-02 08:15:00', 1, [], 'momo');
        // Yesterday: Kira 2 plates — the comparison period for "today".
        $this->sale($kira, $admin, '2026-10-01 09:00:00', 2);

        $response = $this->actingAs($admin)->getJson('/api/reports/branches?from=2026-10-02&to=2026-10-02');

        $response->assertOk();
        $this->assertEquals(104000, $response->json('totals.revenue'));
        $this->assertEquals(50000, $response->json('totals.previous_revenue'));
        $this->assertEquals(108.0, $response->json('totals.change_pct'));
        $this->assertEquals(4, $response->json('totals.plates_sold'));
        $this->assertEquals(2, $response->json('totals.drinks_sold'));
        $this->assertEquals('2026-10-01', $response->json('previous_period.from'));

        $branches = collect($response->json('branches'))->keyBy('store_name');
        $this->assertEquals(79000, $branches['Kira']['revenue']);
        $this->assertEquals(58.0, $branches['Kira']['change_pct']);
        $this->assertEquals(4000, $branches['Kira']['drink_revenue']);
        $this->assertEquals(76.0, $branches['Kira']['share_pct']);
        $this->assertEquals(25000, $branches['Town']['revenue']);
        $this->assertNull($branches['Town']['change_pct']);
        $this->assertEquals(25000, $branches['Town']['by_payment_method']['momo']);
        $this->assertSame('Kira', $response->json('branches.0.store_name'), 'Main store is listed first');
    }

    public function test_days_and_hours_follow_kampala_time_not_utc(): void
    {
        $admin = User::factory()->create(['role' => User::ROLE_ADMIN, 'store_id' => null]);
        $store = Store::factory()->create();

        // 22:30 UTC on 1 Oct is 01:30 on 2 Oct in Kampala.
        $this->sale($store, $admin, '2026-10-01 22:30:00', 1);
        // 20:59 UTC on 1 Oct is 23:59 on 1 Oct in Kampala — yesterday.
        $this->sale($store, $admin, '2026-10-01 20:59:00', 1);

        $response = $this->actingAs($admin)->getJson('/api/reports/branches');

        $response->assertOk();
        $this->assertEquals('2026-10-02', $response->json('period.from'), 'Defaults to today in Kampala');
        $this->assertEquals(25000, $response->json('totals.revenue'));
        $this->assertEquals(25000, $response->json('totals.previous_revenue'));
        $this->assertEquals(25000, $response->json('hourly.1.revenue'));
        $this->assertEquals(0, $response->json('hourly.22.revenue'));
    }

    public function test_daily_series_covers_every_day_in_the_period(): void
    {
        $admin = User::factory()->create(['role' => User::ROLE_ADMIN, 'store_id' => null]);
        $store = Store::factory()->create();
        $this->sale($store, $admin, '2026-09-28 10:00:00', 2);
        $this->sale($store, $admin, '2026-09-30 10:00:00', 1);

        $response = $this->actingAs($admin)->getJson('/api/reports/branches?from=2026-09-26&to=2026-10-02');

        $response->assertOk();
        $daily = collect($response->json('daily'))->keyBy('date');
        $this->assertCount(7, $daily);
        $this->assertEquals(50000, $daily['2026-09-28']['revenue']);
        $this->assertEquals(0, $daily['2026-09-29']['revenue']);
        $this->assertEquals(25000, $daily['2026-09-30']['by_store'][$store->id]);
        $this->assertEquals('2026-09-19', $response->json('previous_period.from'));
        $this->assertEquals('2026-09-25', $response->json('previous_period.to'));
    }

    public function test_branch_detail_shows_cashiers_drinks_payments_stock_and_transfers(): void
    {
        $admin = User::factory()->create(['role' => User::ROLE_ADMIN, 'store_id' => null]);
        $kira = Store::factory()->create(['is_main' => true]);
        $lugogo = Store::factory()->create(['name' => 'Lugogo']);
        $sarah = User::factory()->create(['name' => 'Sarah', 'role' => User::ROLE_CASHIER, 'store_id' => $lugogo->id]);
        $peter = User::factory()->create(['name' => 'Peter', 'role' => User::ROLE_CASHIER, 'store_id' => $lugogo->id]);
        $soda = Item::factory()->create(['name' => 'Soda', 'is_drink' => true]);
        $juice = Item::factory()->create(['name' => 'Passion Juice', 'is_drink' => true]);
        $rice = Item::factory()->create(['name' => 'Rice', 'unit' => 'kg']);

        $this->sale($lugogo, $sarah, '2026-10-02 07:00:00', 2, [[$soda, 3, 2000]]);
        $this->sale($lugogo, $sarah, '2026-10-02 08:00:00', 1, [[$juice, 1, 5000]], 'airtel');
        $this->sale($lugogo, $peter, '2026-10-02 08:30:00', 1);
        // Another branch's sale must not leak in.
        $this->sale($kira, $admin, '2026-10-02 08:00:00', 5);

        ItemStoreSetting::create(['item_id' => $rice->id, 'store_id' => $lugogo->id, 'safety_stock' => 10]);
        StockMovement::create([
            'item_id' => $rice->id, 'store_id' => $lugogo->id, 'type' => StockMovement::TYPE_TRANSFER_IN,
            'qty' => 12, 'user_id' => $admin->id, 'occurred_at' => now()->subDays(3),
        ]);
        StockMovement::create([
            'item_id' => $rice->id, 'store_id' => $lugogo->id, 'type' => StockMovement::TYPE_CONSUMPTION,
            'qty' => -7, 'user_id' => $sarah->id, 'occurred_at' => now()->subHour(),
        ]);

        StockTransfer::create([
            'from_store_id' => $kira->id, 'to_store_id' => $lugogo->id, 'status' => StockTransfer::STATUS_DISCREPANCY,
            'dispatched_by' => $admin->id, 'dispatched_at' => now()->subHours(2),
            'confirmed_by' => $sarah->id, 'confirmed_at' => now()->subHour(),
        ]);
        StockTransfer::create([
            'from_store_id' => $kira->id, 'to_store_id' => $lugogo->id, 'status' => StockTransfer::STATUS_DISPATCHED,
            'dispatched_by' => $admin->id, 'dispatched_at' => now()->subMinutes(30),
        ]);

        $response = $this->actingAs($admin)->getJson("/api/reports/branches/{$lugogo->id}");

        $response->assertOk();
        $this->assertEquals(111000, $response->json('totals.revenue'));
        $this->assertEquals(3, $response->json('totals.sales_count'));
        $this->assertEquals(37000, $response->json('totals.average_sale'));

        $this->assertEquals('Sarah', $response->json('by_cashier.0.name'));
        $this->assertEquals(86000, $response->json('by_cashier.0.revenue'));
        $this->assertEquals(3, $response->json('by_cashier.0.plates_sold'));

        $this->assertEquals('Soda', $response->json('drinks.0.name'));
        $this->assertEquals(3, $response->json('drinks.0.qty'));

        $methods = collect($response->json('by_payment_method'))->keyBy('method');
        $this->assertEquals(30000, $methods['airtel']['revenue']);
        $this->assertEquals(81000, $methods['cash']['revenue']);

        $this->assertEquals('Rice', $response->json('stock_used.0.name'));
        $this->assertEquals(7, $response->json('stock_used.0.qty'));
        $this->assertEquals(1, $response->json('stock.reorder_count'));
        $this->assertEquals('Rice', $response->json('stock.reorder_items.0.item_name'));

        $this->assertEquals(1, $response->json('transfers.received'));
        $this->assertEquals(1, $response->json('transfers.with_discrepancy'));
        $this->assertEquals(1, $response->json('transfers.awaiting_confirmation'));

        $this->assertCount(3, $response->json('recent_sales'));
        $this->assertEquals('1× Plate', $response->json('recent_sales.0.summary'));
        $this->assertEquals('Peter', $response->json('recent_sales.0.sold_by'));
    }

    public function test_store_manager_sees_only_their_own_branch(): void
    {
        $own = Store::factory()->create();
        $other = Store::factory()->create();
        $manager = User::factory()->create(['role' => User::ROLE_STORE_MANAGER, 'store_id' => $own->id]);

        $this->actingAs($manager)->getJson("/api/reports/branches/{$own->id}")->assertOk();
        $this->actingAs($manager)->getJson("/api/reports/branches/{$other->id}")->assertForbidden();
        $this->actingAs($manager)->getJson('/api/reports/branches')->assertForbidden();
    }

    public function test_cashier_cannot_view_branch_reports(): void
    {
        $store = Store::factory()->create();
        $cashier = User::factory()->create(['role' => User::ROLE_CASHIER, 'store_id' => $store->id]);

        $this->actingAs($cashier)->getJson("/api/reports/branches/{$store->id}")->assertForbidden();
    }

    public function test_period_is_validated(): void
    {
        $admin = User::factory()->create(['role' => User::ROLE_ADMIN, 'store_id' => null]);

        $this->actingAs($admin)->getJson('/api/reports/branches?from=2026-10-02&to=2026-10-01')
            ->assertUnprocessable();
        $this->actingAs($admin)->getJson('/api/reports/branches?from=2024-01-01&to=2026-10-01')
            ->assertUnprocessable();
        $this->actingAs($admin)->getJson('/api/reports/branches?from=02-10-2026')
            ->assertUnprocessable();
    }
}
