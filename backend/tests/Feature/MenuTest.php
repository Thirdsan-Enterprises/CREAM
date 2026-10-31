<?php

namespace Tests\Feature;

use App\Models\DrinkPrice;
use App\Models\Item;
use App\Models\ItemStoreSetting;
use App\Models\PlatePrice;
use App\Models\Sale;
use App\Models\SaleItem;
use App\Models\StockMovement;
use App\Models\Store;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * Breakfast items and anything else sold on its own, with or without a plate.
 */
class MenuTest extends TestCase
{
    use RefreshDatabase;

    private User $owner;

    private User $cashier;

    private Store $town;

    private Item $soda;

    protected function setUp(): void
    {
        parent::setUp();

        $this->owner = User::factory()->create(['role' => User::ROLE_ADMIN, 'store_id' => null]);
        Store::factory()->create(['name' => 'Kira', 'is_main' => true]);
        $this->town = Store::factory()->create(['name' => 'Town']);
        $this->cashier = User::factory()->create(['role' => User::ROLE_CASHIER, 'store_id' => $this->town->id]);
        PlatePrice::create(['store_id' => null, 'price' => 25000, 'effective_from' => now()->toDateString(), 'is_active' => true]);

        $this->soda = Item::factory()->create([
            'name' => 'Soda', 'is_drink' => true, 'is_sellable' => true, 'sell_category' => 'Drinks', 'tracks_stock' => true,
        ]);
        ItemStoreSetting::create(['item_id' => $this->soda->id, 'store_id' => $this->town->id, 'safety_stock' => 0]);
        DrinkPrice::create(['item_id' => $this->soda->id, 'store_id' => null, 'price' => 2000, 'effective_from' => now()->toDateString(), 'is_active' => true]);
    }

    private function addToMenu(array $data): int
    {
        return $this->actingAs($this->owner)->postJson('/api/menu-items', $data)->assertCreated()->json('item.id');
    }

    private function stock(int $itemId, float $qty): void
    {
        StockMovement::create([
            'item_id' => $itemId, 'store_id' => $this->town->id, 'type' => StockMovement::TYPE_TRANSFER_IN,
            'qty' => $qty, 'user_id' => $this->owner->id, 'occurred_at' => now(),
        ]);
    }

    private function sell(array $lines)
    {
        return $this->actingAs($this->cashier)->postJson('/api/sales', ['payment_method' => 'cash', 'lines' => $lines]);
    }

    public function test_the_owner_puts_breakfast_items_on_the_menu_with_branch_prices(): void
    {
        $tea = $this->addToMenu(['name' => 'Tea', 'unit' => 'cup', 'category' => 'Breakfast', 'price' => 1000, 'tracks_stock' => false]);
        $egg = $this->addToMenu(['name' => 'Egg', 'unit' => 'piece', 'category' => 'Breakfast', 'price' => 1500]);
        $this->actingAs($this->owner)->patchJson("/api/menu-items/{$egg}", ['price' => 1200, 'store_id' => $this->town->id])->assertOk();

        $menu = collect($this->actingAs($this->cashier)->getJson('/api/menu')->json())->keyBy('item.name');

        $this->assertSame(['Egg', 'Soda', 'Tea'], $menu->keys()->sort()->values()->all());
        $this->assertSame('Breakfast', $menu['Tea']['category']);
        $this->assertSame('Drinks', $menu['Soda']['category']);
        $this->assertEquals(1000, $menu['Tea']['price']);
        $this->assertEquals(1200, $menu['Egg']['price'], 'Town has its own egg price');
        $this->assertNull($menu['Tea']['balance'], 'Tea is made to order; no stock to show');
        $this->assertEquals(0, $menu['Egg']['balance']);
        $this->assertFalse(Item::find($tea)->is_drink, 'Breakfast items come from procurement, not bought at the branch');
        $this->assertNotNull($this->actingAs($this->owner)->getJson("/api/stock/status?store_id={$this->town->id}")->json('items'));
    }

    public function test_items_can_be_sold_on_their_own_without_a_plate(): void
    {
        $tea = $this->addToMenu(['name' => 'Tea', 'category' => 'Breakfast', 'price' => 1000, 'tracks_stock' => false]);

        $sale = $this->sell([['item_type' => 'item', 'item_id' => $tea, 'qty' => 2]]);

        $sale->assertCreated();
        $this->assertEquals(2000, $sale->json('total'));
        $this->assertSame(SaleItem::TYPE_ITEM, SaleItem::first()->item_type);
        $this->assertSame(0, StockMovement::count(), 'Tea does not touch stock');
    }

    public function test_an_item_that_tracks_stock_is_limited_and_deducted(): void
    {
        $egg = $this->addToMenu(['name' => 'Egg', 'category' => 'Breakfast', 'price' => 1500]);

        $this->sell([['item_type' => 'item', 'item_id' => $egg, 'qty' => 1]])
            ->assertUnprocessable()
            ->assertJsonPath('errors.lines.0', 'Only 0 Egg in stock at Town: cannot sell 1. Record the purchase first.');

        $this->stock($egg, 30);
        $this->sell([['item_type' => 'item', 'item_id' => $egg, 'qty' => 4]])->assertCreated();

        $row = collect($this->actingAs($this->cashier)->getJson('/api/stock/status')->json('items'))->firstWhere('item_name', 'Egg');
        $this->assertEquals(26, $row['balance']);
    }

    public function test_a_drink_without_a_plate_works_even_from_the_older_app(): void
    {
        $this->stock($this->soda->id, 10);

        // The app on phones today sends "0 plates" alongside the drink.
        $this->sell([
            ['item_type' => 'plate', 'qty' => 0],
            ['item_type' => 'drink', 'item_id' => $this->soda->id, 'qty' => 1],
        ])->assertCreated()->assertJsonPath('total', '2000.00');

        $this->assertSame(1, SaleItem::count(), 'The empty plate line is not stored');
        $this->assertSame(SaleItem::TYPE_DRINK, SaleItem::first()->item_type);
    }

    public function test_a_sale_with_nothing_on_it_is_refused(): void
    {
        $this->sell([['item_type' => 'plate', 'qty' => 0]])
            ->assertUnprocessable()
            ->assertJsonPath('errors.lines.0', 'Add at least one plate or item to the sale.');
        $this->assertSame(0, Sale::count());
    }

    public function test_a_kitchen_item_not_on_the_menu_cannot_be_sold(): void
    {
        $rice = Item::factory()->create(['name' => 'Rice', 'is_drink' => false, 'is_sellable' => false]);

        $this->sell([['item_type' => 'item', 'item_id' => $rice->id, 'qty' => 1]])
            ->assertUnprocessable()
            ->assertJsonPath('errors.lines.0', 'Rice is not on the menu.');
    }

    public function test_an_existing_stock_item_can_be_added_to_the_menu(): void
    {
        $eggs = Item::factory()->create(['name' => 'Eggs', 'unit' => 'piece', 'is_sellable' => false]);

        $this->addToMenu(['item_id' => $eggs->id, 'category' => 'Breakfast', 'price' => 1500]);

        $this->assertTrue($eggs->fresh()->is_sellable);
        $this->actingAs($this->owner)->postJson('/api/menu-items', ['item_id' => $eggs->id, 'category' => 'Breakfast', 'price' => 1500])
            ->assertUnprocessable();
    }

    public function test_reports_keep_plates_drinks_and_other_items_apart(): void
    {
        $tea = $this->addToMenu(['name' => 'Tea', 'category' => 'Breakfast', 'price' => 1000, 'tracks_stock' => false]);
        $this->stock($this->soda->id, 10);
        $this->sell([
            ['item_type' => 'plate', 'qty' => 1],
            ['item_type' => 'item', 'item_id' => $this->soda->id, 'qty' => 1],
            ['item_type' => 'item', 'item_id' => $tea, 'qty' => 3],
        ])->assertCreated()->assertJsonPath('total', '30000.00');

        $summary = $this->actingAs($this->cashier)->getJson('/api/sales/summary')->json();
        $this->assertEquals(25000, $summary['plate_revenue']);
        $this->assertEquals(2000, $summary['drink_revenue']);
        $this->assertEquals(3000, $summary['item_revenue']);
        $this->assertEquals(30000, $summary['total_revenue']);
        $this->assertEquals(3, $summary['items_sold']);

        $branch = $this->actingAs($this->owner)->getJson("/api/reports/branches/{$this->town->id}")->json();
        $this->assertEquals(3000, $branch['totals']['item_revenue']);
        $menu = collect($branch['menu_items'])->keyBy('name');
        $this->assertSame('Breakfast', $menu['Tea']['category']);
        $this->assertSame('Drinks', $menu['Soda']['category']);
    }

    public function test_only_the_owner_changes_the_menu(): void
    {
        $this->actingAs($this->cashier)->postJson('/api/menu-items', ['name' => 'Tea', 'category' => 'Breakfast', 'price' => 1000])
            ->assertForbidden();
    }
}
