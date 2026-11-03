<?php

namespace Tests\Feature;

use App\Models\EditLog;
use App\Models\Item;
use App\Models\SaleItem;
use App\Models\Store;
use App\Models\User;
use Database\Seeders\DatabaseSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Collection;
use Tests\TestCase;

/**
 * The menu Cream sent: Town and Kira share a lunch menu priced by the sauce
 * and a breakfast menu; Lugogo keeps its own. Lunch dishes count as plates.
 */
class BranchMenuTest extends TestCase
{
    use RefreshDatabase;

    private Store $kira;

    private Store $town;

    private Store $lugogo;

    private User $owner;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(DatabaseSeeder::class);
        $this->artisan('cream:load-menu')->assertSuccessful();
        $this->kira = Store::where('code', 'KIRA')->firstOrFail();
        $this->town = Store::where('code', 'TOWN')->firstOrFail();
        $this->lugogo = Store::where('code', 'LUGOGO')->firstOrFail();
        $this->owner = User::where('role', User::ROLE_ADMIN)->firstOrFail();
    }

    private function cashierAt(Store $store): User
    {
        return User::factory()->create(['role' => User::ROLE_CASHIER, 'store_id' => $store->id]);
    }

    private function menu(User $user): Collection
    {
        return collect($this->actingAs($user)->getJson('/api/menu')->assertOk()->json())->keyBy('item.name');
    }

    public function test_town_and_kira_get_the_menu_lugogo_keeps_its_own(): void
    {
        $town = $this->menu($this->cashierAt($this->town));
        $this->assertEquals(10000, $town['Beef']['price']);
        $this->assertEquals(12000, $town['Fish']['price']);
        $this->assertEquals(3000, $town['Milk Tea']['price']);
        $this->assertEquals(1500, $town['Samosa (Meat)']['price']);
        $this->assertEquals(1500, $town['Water']['price'], 'Town water is 1,500');
        $this->assertSame('Lunch', $town->first()['category'], 'lunch comes first');

        $this->assertTrue($this->menu($this->cashierAt($this->kira))->has('Beef'));

        $lugogo = $this->menu($this->cashierAt($this->lugogo));
        $this->assertFalse($lugogo->has('Beef'));
        $this->assertFalse($lugogo->has('Milk Tea'));
        $this->assertEquals(2000, $lugogo['Water']['price'], 'Lugogo keeps its drink prices');
    }

    public function test_a_lunch_dish_is_a_plate_with_its_name(): void
    {
        $cashier = $this->cashierAt($this->town);
        $town = $this->menu($cashier);
        $sale = $this->actingAs($cashier)->postJson('/api/sales', ['payment_method' => 'cash', 'lines' => [
            ['item_type' => 'item', 'item_id' => $town['Beef']['item']['id'], 'qty' => 2],
            ['item_type' => 'item', 'item_id' => $town['Fish']['item']['id'], 'qty' => 1],
            ['item_type' => 'item', 'item_id' => $town['Milk Tea']['item']['id'], 'qty' => 1],
        ]])->assertCreated();
        $this->assertEquals(35000, $sale->json('total'));
        $this->assertSame(3, SaleItem::where('item_type', SaleItem::TYPE_PLATE)->sum('qty') + 0);

        $summary = $this->actingAs($this->owner)->getJson("/api/sales/summary?store_id={$this->town->id}")->json();
        $this->assertEquals(3, $summary['plates_sold']);
        $this->assertEquals(32000, $summary['plate_revenue']);
        $this->assertEquals(3000, $summary['item_revenue']);

        $report = $this->actingAs($this->owner)->getJson("/api/reports/branches/{$this->town->id}")->json('menu_items');
        $beef = collect($report)->firstWhere('name', 'Beef');
        $this->assertSame('Lunch', $beef['category']);
        $this->assertEquals(2, $beef['qty']);
    }

    public function test_a_dish_cannot_be_sold_where_it_is_not_on_the_menu(): void
    {
        $beef = Item::where('name', 'Beef')->firstOrFail();
        $this->actingAs($this->cashierAt($this->lugogo))->postJson('/api/sales', ['payment_method' => 'cash', 'lines' => [
            ['item_type' => 'item', 'item_id' => $beef->id, 'qty' => 1],
        ]])->assertUnprocessable()->assertJsonPath('errors.lines.0', 'Beef is not on the menu at Lugogo.');
    }

    public function test_dishes_are_not_kitchen_stock(): void
    {
        $manager = User::factory()->create(['role' => User::ROLE_STORE_MANAGER, 'store_id' => $this->town->id]);
        $names = collect($this->actingAs($manager)->getJson('/api/stock/status')->json('items'))->pluck('item_name');
        $this->assertContains('Rice', $names);
        $this->assertContains('Minute Maid', $names, 'drinks are counted');
        $this->assertNotContains('Beef', $names);
        $this->assertNotContains('Milk Tea', $names);

        $items = collect($this->actingAs($manager)->getJson('/api/items')->json('data'))->pluck('name');
        $this->assertNotContains('Chapati', $items);
    }

    public function test_the_owner_chooses_where_a_dish_is_sold(): void
    {
        $beef = Item::where('name', 'Beef')->firstOrFail();
        $this->actingAs($this->owner)->patchJson("/api/menu-items/{$beef->id}", [
            'branches' => [$this->town->id, $this->kira->id, $this->lugogo->id], 'reason' => 'Lugogo starts beef lunch',
        ])->assertOk();
        $this->assertTrue($this->menu($this->cashierAt($this->lugogo))->has('Beef'));

        $log = EditLog::latest('id')->first();
        $this->assertSame('All branches', $log->changes['sold_at']['to']);

        $row = collect($this->actingAs($this->owner)->getJson('/api/price-list')->json('items'))->firstWhere('item.name', 'Beef');
        $this->assertTrue(collect($row['branches'])->every(fn ($b) => $b['on_menu']));
    }

    public function test_breakfast_cassava_is_a_dish_not_the_kitchen_cassava(): void
    {
        $dish = Item::where('name', 'Cassava')->where('is_sellable', true)->sole();
        $this->assertFalse((bool) $dish->tracks_stock);
        $kitchen = Item::where('name', 'Cassava')->where('is_sellable', false)->sole();
        $this->assertTrue((bool) $kitchen->tracks_stock);

        $cashier = $this->cashierAt($this->town);
        $this->actingAs($cashier)->postJson('/api/sales', ['payment_method' => 'cash', 'lines' => [
            ['item_type' => 'item', 'item_id' => $dish->id, 'qty' => 2],
        ]])->assertCreated()->assertJsonPath('total', '1000.00');
    }

    public function test_loading_the_menu_twice_changes_nothing(): void
    {
        $count = Item::count();
        $this->artisan('cream:load-menu')->assertSuccessful();
        $this->assertSame($count, Item::count());
    }
}
