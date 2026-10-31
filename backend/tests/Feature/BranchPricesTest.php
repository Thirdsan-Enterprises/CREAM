<?php

namespace Tests\Feature;

use App\Models\DrinkPrice;
use App\Models\EditLog;
use App\Models\Item;
use App\Models\PlatePrice;
use App\Models\Store;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * Town sells its plate at 15,000 while the other branches charge 25,000.
 * Every price change says why, and the owner can see who changed what.
 */
class BranchPricesTest extends TestCase
{
    use RefreshDatabase;

    private User $owner;

    private Store $kira;

    private Store $town;

    protected function setUp(): void
    {
        parent::setUp();
        $this->owner = User::factory()->create(['role' => User::ROLE_ADMIN, 'store_id' => null, 'name' => 'Owner']);
        $this->kira = Store::factory()->create(['name' => 'Kira', 'is_main' => true]);
        $this->town = Store::factory()->create(['name' => 'Town']);
        PlatePrice::create(['store_id' => null, 'price' => 25000, 'effective_from' => now()->toDateString(), 'is_active' => true]);
    }

    public function test_town_gets_its_own_plate_price_and_the_change_is_logged(): void
    {
        $this->actingAs($this->owner)->patchJson('/api/plate-price', [
            'store_id' => $this->town->id, 'price' => 15000, 'reason' => 'Town customers pay less',
        ])->assertCreated()->assertJson(['price' => 15000, 'own_price' => true]);

        $this->actingAs($this->owner)->getJson('/api/plate-price?store_id='.$this->town->id)->assertJson(['price' => 15000]);
        $this->actingAs($this->owner)->getJson('/api/plate-price?store_id='.$this->kira->id)->assertJson(['price' => 25000]);

        $log = EditLog::sole();
        $this->assertSame('Plate price at Town', $log->subject_label);
        $this->assertSame('price_changed', $log->action);
        $this->assertEquals(['price' => ['from' => 25000, 'to' => 15000]], $log->changes);
        $this->assertSame('Town customers pay less', $log->reason);
        $this->assertSame($this->town->id, $log->store_id);

        $list = $this->actingAs($this->owner)->getJson('/api/price-list')->assertOk();
        $branches = collect($list->json('plate.branches'))->keyBy('store_name');
        $this->assertEquals(15000, $branches['Town']['price']);
        $this->assertTrue($branches['Town']['own']);
        $this->assertEquals(25000, $branches['Kira']['price']);
        $this->assertFalse($branches['Kira']['own']);
    }

    public function test_a_price_change_needs_a_reason(): void
    {
        $this->actingAs($this->owner)->patchJson('/api/plate-price', ['price' => 26000])
            ->assertUnprocessable()->assertJsonPath('errors.reason.0', 'Say why the price is changing.');
        $this->assertSame(0, EditLog::count());
    }

    public function test_a_branch_can_go_back_to_the_price_for_all_branches(): void
    {
        $this->actingAs($this->owner)->patchJson('/api/plate-price', ['store_id' => $this->town->id, 'price' => 15000, 'reason' => 'Trial']);
        $this->actingAs($this->owner)->patchJson('/api/plate-price', [
            'store_id' => $this->town->id, 'use_default' => true, 'reason' => 'Trial over',
        ])->assertCreated()->assertJson(['price' => 25000, 'own_price' => false]);

        $this->assertSame('price_reset', EditLog::latest('id')->first()->action);
    }

    public function test_menu_item_prices_per_branch_appear_in_the_price_list(): void
    {
        $tea = Item::factory()->create(['name' => 'Tea', 'is_sellable' => true, 'sell_category' => 'Breakfast', 'tracks_stock' => false]);
        DrinkPrice::create(['item_id' => $tea->id, 'store_id' => null, 'price' => 1000, 'effective_from' => now()->toDateString(), 'is_active' => true]);

        $this->actingAs($this->owner)->patchJson("/api/menu-items/{$tea->id}", [
            'store_id' => $this->town->id, 'price' => 800, 'reason' => 'Town price',
        ])->assertOk();

        $row = collect($this->actingAs($this->owner)->getJson('/api/price-list')->json('items'))->firstWhere('item.name', 'Tea');
        $this->assertEquals(1000, $row['default']);
        $town = collect($row['branches'])->firstWhere('store_name', 'Town');
        $this->assertEquals(800, $town['price']);
        $this->assertTrue($town['own']);

        $log = EditLog::sole();
        $this->assertSame('Tea at Town', $log->subject_label);
        $this->assertEquals(['price' => ['from' => 1000, 'to' => 800]], $log->changes);
    }

    public function test_the_owner_sees_changes_and_a_manager_only_their_branch(): void
    {
        $this->actingAs($this->owner)->patchJson('/api/plate-price', ['store_id' => $this->town->id, 'price' => 15000, 'reason' => 'Town']);
        $this->actingAs($this->owner)->patchJson('/api/plate-price', ['store_id' => $this->kira->id, 'price' => 27000, 'reason' => 'Kira']);

        $this->actingAs($this->owner)->getJson('/api/edit-logs')->assertOk()
            ->assertJsonCount(2, 'data')
            ->assertJsonPath('data.0.user.name', 'Owner');

        $manager = User::factory()->create(['role' => User::ROLE_STORE_MANAGER, 'store_id' => $this->town->id]);
        $this->actingAs($manager)->getJson('/api/edit-logs?store_id='.$this->kira->id)->assertOk()
            ->assertJsonCount(1, 'data')
            ->assertJsonPath('data.0.reason', 'Town');

        $cashier = User::factory()->create(['role' => User::ROLE_CASHIER, 'store_id' => $this->town->id]);
        $this->actingAs($cashier)->getJson('/api/edit-logs')->assertForbidden();
        $this->actingAs($cashier)->getJson('/api/price-list')->assertForbidden();
    }
}
