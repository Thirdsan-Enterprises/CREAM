<?php

namespace Tests\Feature;

use App\Models\DrinkPrice;
use App\Models\Item;
use App\Models\ItemStoreSetting;
use App\Models\PlatePrice;
use App\Models\Sale;
use App\Models\StockMovement;
use App\Models\Store;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * A drink can only be sold if the branch has it. The user manual says so
 * (chapter 5); if the rule changes, change the manual.
 */
class DrinkStockLimitTest extends TestCase
{
    use RefreshDatabase;

    private Store $store;

    private User $cashier;

    private Item $water;

    protected function setUp(): void
    {
        parent::setUp();

        $this->store = Store::factory()->create(['name' => 'Lugogo']);
        $this->cashier = User::factory()->create(['role' => User::ROLE_CASHIER, 'store_id' => $this->store->id]);
        $this->water = Item::factory()->create(['name' => 'Water', 'is_drink' => true]);
        ItemStoreSetting::create(['item_id' => $this->water->id, 'store_id' => $this->store->id, 'safety_stock' => 2]);
        DrinkPrice::create([
            'item_id' => $this->water->id, 'store_id' => null, 'price' => 2000,
            'effective_from' => now()->toDateString(), 'is_active' => true,
        ]);
        PlatePrice::create(['store_id' => null, 'price' => 25000, 'effective_from' => now()->toDateString(), 'is_active' => true]);
    }

    private function stock(float $qty): void
    {
        StockMovement::create([
            'item_id' => $this->water->id, 'store_id' => $this->store->id, 'type' => StockMovement::TYPE_PURCHASE,
            'qty' => $qty, 'user_id' => $this->cashier->id, 'occurred_at' => now(),
        ]);
    }

    private function sell(array $drinkLines, array $extra = [])
    {
        return $this->actingAs($this->cashier)->postJson('/api/sales', [
            'payment_method' => 'cash',
            'lines' => [
                ['item_type' => 'plate', 'qty' => 1],
                ...array_map(fn ($qty) => ['item_type' => 'drink', 'item_id' => $this->water->id, 'qty' => $qty], $drinkLines),
            ],
            ...$extra,
        ]);
    }

    public function test_a_drink_with_none_in_stock_cannot_be_sold_and_nothing_is_recorded(): void
    {
        $this->sell([3])->assertUnprocessable()
            ->assertJsonPath('errors.lines.0', 'Only 0 Water in stock at Lugogo: cannot sell 3. Record the purchase first.');

        $this->assertSame(0, Sale::count(), 'The plate on the same sale must not be recorded either');
        $this->assertSame(0, StockMovement::where('type', StockMovement::TYPE_CONSUMPTION)->count());
    }

    public function test_it_can_be_sold_up_to_what_is_in_stock_and_not_beyond(): void
    {
        $this->stock(5);

        $this->sell([5])->assertCreated();
        $this->sell([1])->assertUnprocessable()
            ->assertJsonPath('errors.lines.0', 'Only 0 Water in stock at Lugogo: cannot sell 1. Record the purchase first.');
    }

    public function test_a_drink_split_over_several_lines_is_added_up(): void
    {
        $this->stock(4);

        $this->sell([2, 3])->assertUnprocessable();
        $this->sell([2, 2])->assertCreated();
    }

    public function test_a_negative_balance_is_reported_as_none_left(): void
    {
        $this->stock(1);
        StockMovement::create([
            'item_id' => $this->water->id, 'store_id' => $this->store->id, 'type' => StockMovement::TYPE_ADJUSTMENT,
            'qty' => -3, 'user_id' => $this->cashier->id, 'occurred_at' => now(),
        ]);

        $this->sell([1])->assertUnprocessable()->assertJsonPath('errors.lines.0', 'Only 0 Water in stock at Lugogo: cannot sell 1. Record the purchase first.');
    }

    public function test_the_drinks_list_says_how_many_the_branch_has(): void
    {
        $this->stock(7);

        $water = collect($this->actingAs($this->cashier)->getJson('/api/drinks')->json())
            ->first(fn ($d) => $d['item']['name'] === 'Water');

        $this->assertEquals(7, $water['balance']);
    }

    public function test_selling_plates_only_never_needs_stock(): void
    {
        $this->actingAs($this->cashier)->postJson('/api/sales', [
            'payment_method' => 'cash',
            'lines' => [['item_type' => 'plate', 'qty' => 2]],
        ])->assertCreated();
    }
}
