<?php

namespace Tests\Feature;

use App\Models\Item;
use App\Models\ItemStoreSetting;
use App\Models\StockMovement;
use App\Models\Store;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class StockBalanceTest extends TestCase
{
    use RefreshDatabase;

    public function test_balance_is_sum_of_signed_movements_and_status_flips_at_safety_stock(): void
    {
        $kira = Store::factory()->create(['is_main' => true]);
        $item = Item::factory()->create();
        ItemStoreSetting::create(['item_id' => $item->id, 'store_id' => $kira->id, 'safety_stock' => 10]);
        $user = User::factory()->create(['role' => User::ROLE_ADMIN, 'store_id' => null]);

        StockMovement::create([
            'item_id' => $item->id, 'store_id' => $kira->id, 'type' => StockMovement::TYPE_PURCHASE,
            'qty' => 50, 'user_id' => $user->id, 'occurred_at' => now(),
        ]);
        StockMovement::create([
            'item_id' => $item->id, 'store_id' => $kira->id, 'type' => StockMovement::TYPE_CONSUMPTION,
            'qty' => -45, 'user_id' => $user->id, 'occurred_at' => now(),
        ]);

        $response = $this->actingAs($user)->getJson("/api/items/{$item->id}/balances");

        $response->assertOk();
        $balance = collect($response->json('balances'))->firstWhere('store_id', $kira->id);
        $this->assertEquals(5, $balance['balance']);
        $this->assertEquals('Re-Order', $balance['status']);

        StockMovement::create([
            'item_id' => $item->id, 'store_id' => $kira->id, 'type' => StockMovement::TYPE_PURCHASE,
            'qty' => 20, 'user_id' => $user->id, 'occurred_at' => now(),
        ]);

        $response = $this->actingAs($user)->getJson("/api/items/{$item->id}/balances");
        $balance = collect($response->json('balances'))->firstWhere('store_id', $kira->id);
        $this->assertEquals(25, $balance['balance']);
        $this->assertEquals('Stock Sufficient', $balance['status']);
    }

    public function test_purchase_is_rejected_at_a_non_main_store(): void
    {
        $lugogo = Store::factory()->create(['is_main' => false]);
        $item = Item::factory()->create();
        $user = User::factory()->create(['role' => User::ROLE_STORE_MANAGER, 'store_id' => $lugogo->id]);

        $response = $this->actingAs($user)->postJson('/api/stock/purchase', [
            'item_id' => $item->id,
            'qty' => 10,
        ]);

        $response->assertStatus(422);
    }

    public function test_cashier_supplied_store_id_is_overridden_by_their_own_store(): void
    {
        $ownStore = Store::factory()->create();
        $otherStore = Store::factory()->create();
        $item = Item::factory()->create();
        $user = User::factory()->create(['role' => User::ROLE_CASHIER, 'store_id' => $ownStore->id]);

        $response = $this->actingAs($user)->postJson('/api/stock/consumption', [
            'store_id' => $otherStore->id,
            'item_id' => $item->id,
            'qty' => 5,
        ]);

        $response->assertCreated();
        $this->assertDatabaseHas('stock_movements', [
            'item_id' => $item->id,
            'store_id' => $ownStore->id,
            'qty' => -5,
        ]);
        $this->assertDatabaseMissing('stock_movements', [
            'item_id' => $item->id,
            'store_id' => $otherStore->id,
        ]);
    }
}
