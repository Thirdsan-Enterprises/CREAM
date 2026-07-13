<?php

namespace Tests\Feature;

use App\Models\CateringOrder;
use App\Models\CateringPackage;
use App\Models\PlatePrice;
use App\Models\Store;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class CateringTest extends TestCase
{
    use RefreshDatabase;

    public function test_admin_can_create_a_catering_order_with_computed_total(): void
    {
        $admin = User::factory()->create(['role' => User::ROLE_ADMIN, 'store_id' => null]);
        $package = CateringPackage::factory()->create(['price_per_plate' => 38000]);

        $response = $this->actingAs($admin)->postJson('/api/catering-orders', [
            'client_name' => 'Jane Doe',
            'client_phone' => '0700123456',
            'event_name' => 'Wedding',
            'event_date' => now()->addWeek()->toDateString(),
            'catering_package_id' => $package->id,
            'number_of_plates' => 100,
        ]);

        $response->assertCreated();
        $this->assertEquals(3800000, $response->json('total_amount'));
        $this->assertEquals('quoted', $response->json('status'));
    }

    public function test_recording_payments_reduces_balance_due(): void
    {
        $admin = User::factory()->create(['role' => User::ROLE_ADMIN, 'store_id' => null]);
        $package = CateringPackage::factory()->create(['price_per_plate' => 34000]);
        $order = CateringOrder::factory()->create([
            'catering_package_id' => $package->id,
            'number_of_plates' => 50,
            'total_amount' => 1700000,
            'created_by' => $admin->id,
        ]);

        $this->actingAs($admin)->postJson("/api/catering-orders/{$order->id}/payments", [
            'amount' => 500000,
            'payment_method' => 'momo',
        ])->assertCreated()->assertJson(['balance_due' => 1200000]);

        $this->actingAs($admin)->postJson("/api/catering-orders/{$order->id}/payments", [
            'amount' => 1200000,
            'payment_method' => 'bank',
        ])->assertCreated()->assertJson(['balance_due' => 0]);
    }

    public function test_status_can_be_updated_through_the_pipeline(): void
    {
        $admin = User::factory()->create(['role' => User::ROLE_ADMIN, 'store_id' => null]);
        $package = CateringPackage::factory()->create();
        $order = CateringOrder::factory()->create([
            'catering_package_id' => $package->id,
            'created_by' => $admin->id,
        ]);

        $this->actingAs($admin)->patchJson("/api/catering-orders/{$order->id}", [
            'status' => 'confirmed',
        ])->assertOk()->assertJson(['status' => 'confirmed']);
    }

    public function test_non_admin_cannot_access_catering(): void
    {
        $store = Store::factory()->create();
        $manager = User::factory()->create(['role' => User::ROLE_STORE_MANAGER, 'store_id' => $store->id]);
        $package = CateringPackage::factory()->create();

        $this->actingAs($manager)->getJson('/api/catering-orders')->assertStatus(403);
        $this->actingAs($manager)->postJson('/api/catering-orders', [
            'client_name' => 'X', 'client_phone' => '070', 'event_date' => now()->toDateString(),
            'catering_package_id' => $package->id, 'number_of_plates' => 10,
        ])->assertStatus(403);
    }

    public function test_catering_revenue_is_excluded_from_sales_summary(): void
    {
        PlatePrice::create([
            'store_id' => null, 'price' => 25000, 'effective_from' => now()->toDateString(), 'is_active' => true,
        ]);
        $store = Store::factory()->create();
        $cashier = User::factory()->create(['role' => User::ROLE_CASHIER, 'store_id' => $store->id]);
        $admin = User::factory()->create(['role' => User::ROLE_ADMIN, 'store_id' => null]);
        $package = CateringPackage::factory()->create(['price_per_plate' => 34000]);

        CateringOrder::factory()->create([
            'catering_package_id' => $package->id,
            'number_of_plates' => 200,
            'total_amount' => 6800000,
            'created_by' => $admin->id,
        ]);

        $this->actingAs($cashier)->postJson('/api/sales', [
            'payment_method' => 'cash',
            'lines' => [['item_type' => 'plate', 'qty' => 1]],
        ])->assertCreated();

        $response = $this->actingAs($cashier)->getJson('/api/sales/summary');

        $this->assertEquals(25000, $response->json('total_revenue'));
    }
}
