<?php

namespace Tests\Feature;

use App\Models\Item;
use App\Models\StockTransfer;
use App\Models\Store;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class StockTransferTest extends TestCase
{
    use RefreshDatabase;

    public function test_dispatch_then_confirm_matching_quantities_marks_transfer_confirmed(): void
    {
        $kira = Store::factory()->create(['is_main' => true]);
        $lugogo = Store::factory()->create(['is_main' => false]);
        $item = Item::factory()->create();
        $storekeeper = User::factory()->create(['role' => User::ROLE_STOREKEEPER, 'store_id' => $kira->id]);
        $manager = User::factory()->create(['role' => User::ROLE_STORE_MANAGER, 'store_id' => $lugogo->id]);

        $dispatch = $this->actingAs($storekeeper)->postJson('/api/transfers', [
            'to_store_id' => $lugogo->id,
            'items' => [['item_id' => $item->id, 'qty' => 20]],
        ])->assertCreated();

        $this->assertDatabaseHas('stock_movements', [
            'item_id' => $item->id, 'store_id' => $kira->id, 'type' => 'transfer_out', 'qty' => -20,
        ]);

        $transferId = $dispatch->json('id');
        $lineId = $dispatch->json('items.0.id');

        $confirm = $this->actingAs($manager)->postJson("/api/transfers/{$transferId}/confirm", [
            'items' => [['stock_transfer_item_id' => $lineId, 'qty_received' => 20]],
        ])->assertOk();

        $this->assertEquals(StockTransfer::STATUS_CONFIRMED, $confirm->json('status'));
        $this->assertDatabaseHas('stock_movements', [
            'item_id' => $item->id, 'store_id' => $lugogo->id, 'type' => 'transfer_in', 'qty' => 20,
        ]);
    }

    public function test_confirm_with_short_quantity_flags_discrepancy(): void
    {
        $kira = Store::factory()->create(['is_main' => true]);
        $lugogo = Store::factory()->create(['is_main' => false]);
        $item = Item::factory()->create();
        $storekeeper = User::factory()->create(['role' => User::ROLE_STOREKEEPER, 'store_id' => $kira->id]);
        $manager = User::factory()->create(['role' => User::ROLE_STORE_MANAGER, 'store_id' => $lugogo->id]);

        $dispatch = $this->actingAs($storekeeper)->postJson('/api/transfers', [
            'to_store_id' => $lugogo->id,
            'items' => [['item_id' => $item->id, 'qty' => 20]],
        ])->assertCreated();

        $transferId = $dispatch->json('id');
        $lineId = $dispatch->json('items.0.id');

        $confirm = $this->actingAs($manager)->postJson("/api/transfers/{$transferId}/confirm", [
            'items' => [['stock_transfer_item_id' => $lineId, 'qty_received' => 18]],
        ])->assertOk();

        $this->assertEquals(StockTransfer::STATUS_DISCREPANCY, $confirm->json('status'));
    }

    public function test_a_transfer_line_can_only_be_confirmed_once(): void
    {
        $kira = Store::factory()->create(['is_main' => true]);
        $lugogo = Store::factory()->create(['is_main' => false]);
        $item = Item::factory()->create();
        $storekeeper = User::factory()->create(['role' => User::ROLE_STOREKEEPER, 'store_id' => $kira->id]);
        $manager = User::factory()->create(['role' => User::ROLE_STORE_MANAGER, 'store_id' => $lugogo->id]);

        $dispatch = $this->actingAs($storekeeper)->postJson('/api/transfers', [
            'to_store_id' => $lugogo->id,
            'items' => [['item_id' => $item->id, 'qty' => 20]],
        ])->assertCreated();

        $transferId = $dispatch->json('id');
        $lineId = $dispatch->json('items.0.id');

        $this->actingAs($manager)->postJson("/api/transfers/{$transferId}/confirm", [
            'items' => [['stock_transfer_item_id' => $lineId, 'qty_received' => 20]],
        ])->assertOk();

        $this->actingAs($manager)->postJson("/api/transfers/{$transferId}/confirm", [
            'items' => [['stock_transfer_item_id' => $lineId, 'qty_received' => 20]],
        ])->assertStatus(422);
    }

    public function test_only_the_receiving_store_can_confirm(): void
    {
        $kira = Store::factory()->create(['is_main' => true]);
        $lugogo = Store::factory()->create(['is_main' => false]);
        $town = Store::factory()->create(['is_main' => false]);
        $item = Item::factory()->create();
        $storekeeper = User::factory()->create(['role' => User::ROLE_STOREKEEPER, 'store_id' => $kira->id]);
        $townManager = User::factory()->create(['role' => User::ROLE_STORE_MANAGER, 'store_id' => $town->id]);

        $dispatch = $this->actingAs($storekeeper)->postJson('/api/transfers', [
            'to_store_id' => $lugogo->id,
            'items' => [['item_id' => $item->id, 'qty' => 20]],
        ])->assertCreated();

        $transferId = $dispatch->json('id');
        $lineId = $dispatch->json('items.0.id');

        $this->actingAs($townManager)->postJson("/api/transfers/{$transferId}/confirm", [
            'items' => [['stock_transfer_item_id' => $lineId, 'qty_received' => 20]],
        ])->assertStatus(403);
    }
}
