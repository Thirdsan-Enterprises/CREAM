<?php

namespace Tests\Feature;

use App\Models\Item;
use App\Models\ItemStoreSetting;
use App\Models\PlatePrice;
use App\Models\StockRequest;
use App\Models\StockTransfer;
use App\Models\Store;
use App\Models\User;
use App\Services\StockService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * The procurement unit buys for everyone and sends to the branches; it has
 * its own login. Branches ask it for what they are missing.
 */
class ProcurementTest extends TestCase
{
    use RefreshDatabase;

    private User $owner;

    private Store $kira;

    private Store $town;

    private User $townManager;

    private User $procurement;

    private Item $rice;

    private Item $oil;

    protected function setUp(): void
    {
        parent::setUp();
        $this->owner = User::factory()->create(['role' => User::ROLE_ADMIN, 'store_id' => null]);
        $this->kira = Store::factory()->create(['name' => 'Kira', 'is_main' => true]);
        $this->town = Store::factory()->create(['name' => 'Town']);
        $this->townManager = User::factory()->create(['role' => User::ROLE_STORE_MANAGER, 'store_id' => $this->town->id]);
        PlatePrice::create(['store_id' => null, 'price' => 25000, 'effective_from' => now()->toDateString(), 'is_active' => true]);

        // The owner opens a procurement login; whatever branch the form
        // sends, it works at the procurement unit.
        $id = $this->actingAs($this->owner)->postJson('/api/users', [
            'name' => 'Procurement', 'phone' => '0700000099', 'password' => 'password123',
            'role' => User::ROLE_STOREKEEPER, 'store_id' => $this->town->id,
        ])->assertCreated()->assertJsonPath('store.name', 'Kira')->json('id');
        $this->procurement = User::find($id);

        foreach (['Rice' => 'kg', 'Cooking oil' => 'litre'] as $name => $unit) {
            $item = Item::factory()->create(['name' => $name, 'unit' => $unit]);
            foreach ([$this->kira, $this->town] as $store) {
                ItemStoreSetting::create(['item_id' => $item->id, 'store_id' => $store->id, 'safety_stock' => 5]);
            }
            $key = $name === 'Rice' ? 'rice' : 'oil';
            $this->{$key} = $item;
        }
    }

    private function buy(Item $item, float $qty): void
    {
        $this->actingAs($this->procurement)->postJson('/api/stock/purchase', ['item_id' => $item->id, 'qty' => $qty])->assertCreated();
    }

    public function test_a_branch_asks_and_procurement_sends_what_it_has(): void
    {
        $this->buy($this->rice, 50);
        $this->buy($this->oil, 4);

        $requestId = $this->actingAs($this->townManager)->postJson('/api/stock-requests', [
            'items' => [['item_id' => $this->rice->id, 'qty' => 20], ['item_id' => $this->oil->id, 'qty' => 10]],
            'note' => 'For the weekend',
        ])->assertCreated()->assertJsonPath('store.name', 'Town')->json('id');

        // Procurement sees it, with what it has on hand.
        $open = $this->actingAs($this->procurement)->getJson('/api/stock-requests?status=open')->assertOk()->json('data.0');
        $this->assertSame('Town', $open['store']['name']);
        $this->assertEquals(4, collect($open['items'])->firstWhere('item.name', 'Cooking oil')['available_at_procurement']);

        // Sending 10 oil fails: only 4 in stock.
        $lines = collect($open['items'])->keyBy('item.name');
        $this->actingAs($this->procurement)->postJson("/api/stock-requests/{$requestId}/send")
            ->assertUnprocessable()->assertJsonPath('errors.items.0', 'Only 4 litre of Cooking oil available at Kira: cannot send 10.');

        $this->actingAs($this->procurement)->postJson("/api/stock-requests/{$requestId}/send", [
            'items' => [['stock_request_item_id' => $lines['Cooking oil']['id'], 'qty' => 4]],
            'note' => 'Only 4 litres left, buying more Monday',
        ])->assertOk()->assertJsonPath('status', 'sent');

        $request = StockRequest::with('items')->find($requestId);
        $transfer = StockTransfer::with('items')->find($request->stock_transfer_id);
        $this->assertSame($this->town->id, $transfer->to_store_id);
        $this->assertEquals([20, 4], $transfer->items->sortBy('item_id')->pluck('qty_dispatched')->map(fn ($q) => (float) $q)->values()->all());
        $this->assertEquals(30, app(StockService::class)->balance($this->rice->id, $this->kira->id));

        // The branch confirms on arrival as with any transfer.
        $this->actingAs($this->townManager)->postJson("/api/transfers/{$transfer->id}/confirm", [
            'items' => $transfer->items->map(fn ($l) => ['stock_transfer_item_id' => $l->id, 'qty_received' => $l->qty_dispatched])->all(),
        ])->assertOk();
        $this->assertEquals(20, app(StockService::class)->balance($this->rice->id, $this->town->id));

        // Answered requests cannot be answered again.
        $this->actingAs($this->procurement)->postJson("/api/stock-requests/{$requestId}/decline", ['reason' => 'x'])->assertUnprocessable();
    }

    public function test_procurement_can_decline_with_a_reason_and_branches_only_see_their_own(): void
    {
        $lugogo = Store::factory()->create(['name' => 'Lugogo']);
        $lugogoCashier = User::factory()->create(['role' => User::ROLE_CASHIER, 'store_id' => $lugogo->id]);

        $id = $this->actingAs($this->townManager)->postJson('/api/stock-requests', [
            'items' => [['item_id' => $this->rice->id, 'qty' => 5]],
        ])->assertCreated()->json('id');

        $this->actingAs($lugogoCashier)->getJson('/api/stock-requests')->assertJsonCount(0, 'data');
        $this->actingAs($lugogoCashier)->getJson("/api/stock-requests/{$id}")->assertForbidden();
        $this->actingAs($this->townManager)->postJson("/api/stock-requests/{$id}/decline", ['reason' => 'x'])->assertForbidden();

        $this->actingAs($this->procurement)->postJson("/api/stock-requests/{$id}/decline", [])
            ->assertUnprocessable()->assertJsonPath('errors.reason.0', 'Tell the branch why.');
        $this->actingAs($this->procurement)->postJson("/api/stock-requests/{$id}/decline", ['reason' => 'Rice comes Friday'])
            ->assertOk()->assertJsonPath('response_note', 'Rice comes Friday');

        $this->actingAs($this->townManager)->getJson('/api/stock-requests')
            ->assertJsonPath('data.0.status', 'declined')
            ->assertJsonPath('data.0.responded_by.name', 'Procurement');
    }

    public function test_procurement_sees_every_branch_stock_but_cannot_sell_or_manage(): void
    {
        $this->actingAs($this->procurement)->getJson('/api/stock/status?store_id='.$this->town->id)->assertOk()->assertJsonPath('store_id', $this->town->id);
        $this->actingAs($this->procurement)->getJson('/api/reports/stock-status')->assertOk();
        $this->actingAs($this->townManager)->getJson('/api/reports/stock-status')->assertForbidden();

        $this->actingAs($this->procurement)->postJson('/api/sales', ['payment_method' => 'cash', 'lines' => [['item_type' => 'plate', 'qty' => 1]]])->assertForbidden();
        $this->actingAs($this->procurement)->getJson('/api/customers')->assertForbidden();
    }

    public function test_a_procurement_unit_of_its_own_does_not_sell_and_takes_over_the_staff(): void
    {
        $unit = Store::factory()->create(['name' => 'Procurement Unit', 'sells' => false]);
        $this->actingAs($this->owner)->patchJson("/api/stores/{$unit->id}", ['is_main' => true])->assertOk()->assertJsonPath('is_main', true);

        $this->assertFalse($this->kira->fresh()->is_main, 'only one procurement unit');
        $this->assertSame($unit->id, $this->procurement->fresh()->store_id, 'procurement staff move with it');

        $this->actingAs($this->owner)->postJson('/api/sales', [
            'store_id' => $unit->id, 'payment_method' => 'cash', 'lines' => [['item_type' => 'plate', 'qty' => 1]],
        ])->assertUnprocessable()->assertJsonPath('errors.store_id.0', 'Procurement Unit is the procurement unit and does not sell. Choose a branch.');

        $names = collect($this->actingAs($this->owner)->getJson('/api/reports/branches?range=today')->json('branches'))->pluck('store_name');
        $this->assertNotContains('Procurement Unit', $names);
        $this->assertContains('Kira', $names);

        // Kira now buys drinks only, like any branch; food is bought by the unit.
        $this->actingAs($this->owner)->postJson('/api/stock/purchase', ['store_id' => $this->kira->id, 'item_id' => $this->rice->id, 'qty' => 5])->assertUnprocessable();
        $this->actingAs($this->owner)->patchJson("/api/stores/{$unit->id}", ['is_main' => false])->assertUnprocessable();
    }

    public function test_the_procurement_unit_cannot_request_from_itself(): void
    {
        $kiraManager = User::factory()->create(['role' => User::ROLE_STORE_MANAGER, 'store_id' => $this->kira->id]);
        $this->actingAs($kiraManager)->postJson('/api/stock-requests', ['items' => [['item_id' => $this->rice->id, 'qty' => 5]]])
            ->assertUnprocessable();
        $this->assertTrue($kiraManager->isProcurement());
    }

    public function test_a_procurement_login_needs_no_branch_on_the_form(): void
    {
        $this->actingAs($this->owner)->postJson('/api/users', [
            'name' => 'Buyer Two', 'phone' => '0700000098', 'password' => 'password123', 'role' => User::ROLE_STOREKEEPER,
        ])->assertCreated()->assertJsonPath('store.name', 'Kira');
    }
}
