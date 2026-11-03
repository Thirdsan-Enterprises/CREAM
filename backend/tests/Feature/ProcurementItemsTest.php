<?php

namespace Tests\Feature;

use App\Models\EditLog;
use App\Models\Item;
use App\Models\Store;
use App\Models\User;
use Database\Seeders\DatabaseSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Collection;
use Tests\TestCase;

/**
 * Procurement keeps its own list of what it buys, separate from the menu,
 * and adds or removes items itself.
 */
class ProcurementItemsTest extends TestCase
{
    use RefreshDatabase;

    private User $procurement;

    private User $cashier;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(DatabaseSeeder::class);
        $this->artisan('cream:load-menu')->assertSuccessful();
        $this->artisan('cream:load-procurement-items')->assertSuccessful();
        $kira = Store::where('is_main', true)->firstOrFail();
        $this->procurement = User::factory()->create(['role' => User::ROLE_STOREKEEPER, 'store_id' => $kira->id]);
        $this->cashier = User::factory()->create(['role' => User::ROLE_CASHIER, 'store_id' => Store::where('code', 'TOWN')->value('id')]);
    }

    private function list(): Collection
    {
        return collect($this->actingAs($this->procurement)->getJson('/api/items')->assertOk()->json('data'))->keyBy('name');
    }

    public function test_the_list_is_grouped_and_kept_apart_from_the_menu(): void
    {
        $items = $this->list();
        $this->assertSame('Packaging & disposables', $items['Serviettes']['category']);
        $this->assertSame('Fuel', $items['Charcoal']['category']);
        $this->assertSame('Food', $items['Rice']['category']);
        $this->assertTrue($items->has('Irish potatoes'), 'the old "Irish" item is renamed, not duplicated');
        $this->assertFalse($items->has('Irish'));
        $this->assertFalse($items->has('Milk Tea'), 'menu dishes are not kitchen stock');
        $this->assertSame(1, Item::where('name', 'Cassava')->where('is_sellable', false)->count());

        $this->actingAs($this->cashier)->getJson('/api/items')->assertForbidden();
    }

    public function test_procurement_adds_an_item_and_cannot_add_it_twice(): void
    {
        $this->actingAs($this->procurement)->postJson('/api/items', [
            'name' => 'Tomatoes', 'unit' => 'kg', 'category' => 'Food', 'safety_stock' => 5,
        ])->assertCreated();
        $this->assertTrue($this->list()->has('Tomatoes'));

        $this->actingAs($this->procurement)->postJson('/api/items', ['name' => 'tomatoes', 'unit' => 'kg'])
            ->assertUnprocessable()->assertJsonPath('errors.name.0', 'Tomatoes is already in kitchen stock.');
        $this->actingAs($this->cashier)->postJson('/api/items', ['name' => 'Onions', 'unit' => 'kg'])->assertForbidden();
    }

    public function test_an_unused_item_is_deleted_and_a_used_one_is_kept_for_the_records(): void
    {
        $unused = Item::where('name', 'Oregano')->firstOrFail();
        $this->actingAs($this->procurement)->deleteJson("/api/items/{$unused->id}", [])
            ->assertUnprocessable()->assertJsonPath('errors.reason.0', 'Say why this item is being removed.');
        $this->actingAs($this->procurement)->deleteJson("/api/items/{$unused->id}", ['reason' => 'We do not use it'])
            ->assertOk()->assertJsonPath('deleted', true);
        $this->assertNull(Item::find($unused->id));

        $sugar = Item::where('name', 'Sugar')->firstOrFail();
        $this->actingAs($this->procurement)->postJson('/api/stock/purchase', ['item_id' => $sugar->id, 'qty' => 10])->assertCreated();
        $this->actingAs($this->procurement)->deleteJson("/api/items/{$sugar->id}", ['reason' => 'Switching to sachets'])
            ->assertOk()->assertJsonPath('deleted', false);
        $this->assertFalse($this->list()->has('Sugar'), 'gone from the list');
        $this->assertNotNull(Item::find($sugar->id), 'history kept');

        // ...and it can come back.
        $this->actingAs($this->procurement)->patchJson("/api/items/{$sugar->id}", ['is_active' => true, 'reason' => 'Back to bags'])->assertOk();
        $this->assertTrue($this->list()->has('Sugar'));
        $this->assertEqualsCanonicalizing(['deleted', 'removed', 'restored'], EditLog::pluck('action')->all());
    }

    public function test_a_menu_dish_cannot_be_removed_from_here(): void
    {
        $tea = Item::where('name', 'Milk Tea')->firstOrFail();
        $this->actingAs($this->procurement)->deleteJson("/api/items/{$tea->id}", ['reason' => 'x'])->assertUnprocessable();
    }

    public function test_mineral_water_is_the_water_drink_not_a_kitchen_item(): void
    {
        Item::create(['name' => 'Mineral water', 'unit' => 'bottle', 'category' => 'Food',
            'is_drink' => false, 'is_sellable' => false, 'tracks_stock' => true, 'is_active' => true]);
        $this->artisan('cream:load-procurement-items')->assertSuccessful();

        $this->assertFalse($this->list()->has('Mineral water'));
        $this->assertDatabaseMissing('items', ['name' => 'Mineral water']);
        $withDrinks = collect($this->actingAs($this->procurement)->getJson('/api/items?with_drinks=1')->json('data'))->keyBy('name');
        $this->assertTrue($withDrinks['Water']['is_drink'], 'procurement buys bottled water as the Water drink');
    }
}
