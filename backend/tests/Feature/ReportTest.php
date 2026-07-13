<?php

namespace Tests\Feature;

use App\Models\CateringOrder;
use App\Models\CateringPackage;
use App\Models\Customer;
use App\Models\Item;
use App\Models\ItemStoreSetting;
use App\Models\LedgerEntry;
use App\Models\Sale;
use App\Models\SaleItem;
use App\Models\StockMovement;
use App\Models\Store;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class ReportTest extends TestCase
{
    use RefreshDatabase;

    public function test_dashboard_aggregates_todays_sales_low_stock_catering_and_credit(): void
    {
        $admin = User::factory()->create(['role' => User::ROLE_ADMIN, 'store_id' => null]);
        $store = Store::factory()->create();
        $item = Item::factory()->create();
        ItemStoreSetting::create(['item_id' => $item->id, 'store_id' => $store->id, 'safety_stock' => 10]);
        StockMovement::create([
            'item_id' => $item->id, 'store_id' => $store->id, 'type' => StockMovement::TYPE_PURCHASE,
            'qty' => 5, 'user_id' => $admin->id, 'occurred_at' => now(),
        ]);

        $sale = Sale::create([
            'store_id' => $store->id, 'sold_by' => $admin->id, 'payment_method' => 'cash',
            'total' => 25000, 'sold_at' => now(),
        ]);
        SaleItem::create([
            'sale_id' => $sale->id, 'item_type' => 'plate', 'qty' => 1, 'unit_price' => 25000, 'line_total' => 25000,
        ]);

        $package = CateringPackage::factory()->create();
        CateringOrder::factory()->create([
            'catering_package_id' => $package->id,
            'event_date' => now()->addDays(3)->toDateString(),
            'created_by' => $admin->id,
        ]);

        $creditCustomer = Customer::factory()->credit(50000)->create();
        LedgerEntry::create([
            'customer_id' => $creditCustomer->id, 'type' => 'sale_debit', 'amount' => -20000,
            'recorded_by' => $admin->id, 'occurred_at' => now(),
        ]);

        $response = $this->actingAs($admin)->getJson('/api/reports/dashboard');

        $response->assertOk();
        $this->assertEquals(25000, $response->json('sales_total_today'));
        $this->assertEquals(1, $response->json('plates_sold_today'));
        $this->assertEquals(20000, $response->json('total_outstanding_credit'));
        $this->assertCount(1, $response->json('upcoming_catering'));
        $lowStock = collect($response->json('low_stock_alerts'));
        $this->assertTrue($lowStock->contains(fn ($row) => $row['item_id'] === $item->id));
    }

    public function test_stock_status_reports_sufficient_and_reorder_per_store(): void
    {
        $admin = User::factory()->create(['role' => User::ROLE_ADMIN, 'store_id' => null]);
        $store = Store::factory()->create();
        $item = Item::factory()->create();
        ItemStoreSetting::create(['item_id' => $item->id, 'store_id' => $store->id, 'safety_stock' => 10]);
        StockMovement::create([
            'item_id' => $item->id, 'store_id' => $store->id, 'type' => StockMovement::TYPE_PURCHASE,
            'qty' => 50, 'user_id' => $admin->id, 'occurred_at' => now(),
        ]);

        $response = $this->actingAs($admin)->getJson('/api/reports/stock-status');

        $response->assertOk();
        $storeRow = collect($response->json())->firstWhere('store_id', $store->id);
        $itemRow = collect($storeRow['items'])->firstWhere('item_id', $item->id);
        $this->assertEquals('Stock Sufficient', $itemRow['status']);
    }

    public function test_outstanding_credit_lists_only_negative_balance_credit_customers(): void
    {
        $admin = User::factory()->create(['role' => User::ROLE_ADMIN, 'store_id' => null]);
        $negative = Customer::factory()->credit(50000)->create();
        LedgerEntry::create([
            'customer_id' => $negative->id, 'type' => 'sale_debit', 'amount' => -15000,
            'recorded_by' => $admin->id, 'occurred_at' => now(),
        ]);
        Customer::factory()->credit(50000)->create();

        $response = $this->actingAs($admin)->getJson('/api/reports/outstanding-credit');

        $response->assertOk();
        $this->assertCount(1, $response->json());
        $this->assertEquals($negative->id, $response->json('0.customer_id'));
    }

    public function test_catering_pipeline_filters_by_status_and_upcoming(): void
    {
        $admin = User::factory()->create(['role' => User::ROLE_ADMIN, 'store_id' => null]);
        $package = CateringPackage::factory()->create();

        CateringOrder::factory()->create([
            'catering_package_id' => $package->id,
            'status' => CateringOrder::STATUS_CONFIRMED,
            'event_date' => now()->addDays(2)->toDateString(),
            'created_by' => $admin->id,
        ]);
        CateringOrder::factory()->create([
            'catering_package_id' => $package->id,
            'status' => CateringOrder::STATUS_SETTLED,
            'event_date' => now()->subDays(10)->toDateString(),
            'created_by' => $admin->id,
        ]);

        $response = $this->actingAs($admin)->getJson('/api/reports/catering-pipeline?status=confirmed');
        $response->assertOk();
        $this->assertCount(1, $response->json());

        $upcoming = $this->actingAs($admin)->getJson('/api/reports/catering-pipeline?upcoming=1');
        $upcoming->assertOk();
        $this->assertCount(1, $upcoming->json());
    }

    public function test_non_admin_cannot_access_reports(): void
    {
        $store = Store::factory()->create();
        $manager = User::factory()->create(['role' => User::ROLE_STORE_MANAGER, 'store_id' => $store->id]);

        $this->actingAs($manager)->getJson('/api/reports/dashboard')->assertStatus(403);
    }
}
