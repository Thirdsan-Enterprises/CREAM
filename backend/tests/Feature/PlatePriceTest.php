<?php

namespace Tests\Feature;

use App\Models\Store;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class PlatePriceTest extends TestCase
{
    use RefreshDatabase;

    public function test_default_plate_price_is_25000_when_none_set(): void
    {
        $admin = User::factory()->create(['role' => User::ROLE_ADMIN, 'store_id' => null]);

        $response = $this->actingAs($admin)->getJson('/api/plate-price');

        $response->assertOk()->assertJson(['price' => 25000]);
    }

    public function test_admin_can_update_global_plate_price(): void
    {
        $admin = User::factory()->create(['role' => User::ROLE_ADMIN, 'store_id' => null]);

        $this->actingAs($admin)->patchJson('/api/plate-price', ['price' => 27000])->assertCreated();

        $this->actingAs($admin)->getJson('/api/plate-price')->assertJson(['price' => 27000]);
    }

    public function test_store_override_takes_precedence_over_global(): void
    {
        $store = Store::factory()->create();
        $admin = User::factory()->create(['role' => User::ROLE_ADMIN, 'store_id' => null]);

        $this->actingAs($admin)->patchJson('/api/plate-price', ['price' => 27000])->assertCreated();
        $this->actingAs($admin)->patchJson('/api/plate-price', ['price' => 30000, 'store_id' => $store->id])->assertCreated();

        $this->actingAs($admin)->getJson("/api/plate-price?store_id={$store->id}")->assertJson(['price' => 30000]);
    }

    public function test_cashier_cannot_update_plate_price(): void
    {
        $store = Store::factory()->create();
        $cashier = User::factory()->create(['role' => User::ROLE_CASHIER, 'store_id' => $store->id]);

        $this->actingAs($cashier)->patchJson('/api/plate-price', ['price' => 27000])->assertStatus(403);
    }
}
