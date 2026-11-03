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
 * The client's second round: Lugogo's two lunches, Kira lunch at 25,000
 * with discounts, plates prepared each day, expenses, purchase prices and
 * each cashier's day.
 */
class NovemberChangesTest extends TestCase
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
        $this->artisan('cream:load-procurement-items')->assertSuccessful();
        $this->kira = Store::where('code', 'KIRA')->firstOrFail();
        $this->town = Store::where('code', 'TOWN')->firstOrFail();
        $this->lugogo = Store::where('code', 'LUGOGO')->firstOrFail();
        $this->owner = User::where('role', User::ROLE_ADMIN)->firstOrFail();
    }

    private function cashier(Store $store, array $extra = []): User
    {
        return User::factory()->create(['role' => User::ROLE_CASHIER, 'store_id' => $store->id, ...$extra]);
    }

    private function menu(User $user): Collection
    {
        return collect($this->actingAs($user)->getJson('/api/menu')->json())->keyBy('item.name');
    }

    private function prepare(User $user, array $plates): void
    {
        $menu = $this->menu($user);
        $this->actingAs($user)->postJson('/api/daily-plates', ['items' => collect($plates)
            ->map(fn ($qty, $name) => ['item_id' => $menu[$name]['item']['id'], 'qty' => $qty])->values()->all()])->assertOk();
    }

    private function sell(User $user, array $lines, array $extra = [])
    {
        $menu = $this->menu($user);

        return $this->actingAs($user)->postJson('/api/sales', ['payment_method' => 'cash', 'lines' => collect($lines)
            ->map(fn ($qty, $name) => ['item_type' => 'item', 'item_id' => $menu[$name]['item']['id'], 'qty' => $qty])->values()->all(), ...$extra]);
    }

    public function test_lugogo_has_its_two_lunches_and_kira_lunch_is_25000(): void
    {
        $lugogo = $this->menu($this->cashier($this->lugogo));
        $this->assertEquals(15000, $lugogo['Full plate']['price']);
        $this->assertEquals(10000, $lugogo['Small plate']['price']);
        $this->assertFalse($lugogo->has('Beef'));

        $kira = $this->menu($this->cashier($this->kira));
        $this->assertEquals(25000, $kira['Beef']['price']);
        $this->assertEquals(25000, $kira['Peas']['price']);
        $this->assertEquals(3000, $kira['Milk Tea']['price'], 'breakfast is the Town price');
        $this->assertEquals(10000, $this->menu($this->cashier($this->town))['Beef']['price']);
        $this->assertFalse($this->menu($this->cashier($this->town))->has('Full plate'));

        // The owner renames and reprices a Lugogo lunch.
        $id = $lugogo['Full plate']['item']['id'];
        $this->actingAs($this->owner)->patchJson("/api/menu-items/{$id}", [
            'name' => 'Matooke & beef', 'price' => 16000, 'store_id' => $this->lugogo->id, 'reason' => 'Lugogo menu names',
        ])->assertOk();
        $this->assertEquals(16000, $this->menu($this->cashier($this->lugogo))['Matooke & beef']['price']);
    }

    public function test_plates_are_prepared_each_morning_and_sell_down(): void
    {
        $cashier = $this->cashier($this->kira);
        $this->sell($cashier, ['Beef' => 1])->assertUnprocessable()
            ->assertJsonPath('errors.lines.0', 'No Beef plates left today at Kira (Main/Warehouse). Add today\'s plates first.');

        $this->prepare($cashier, ['Beef' => 40, 'Fish' => 20]);
        $this->sell($cashier, ['Beef' => 3, 'Fish' => 1])->assertCreated()->assertJsonPath('total', '100000.00');

        $plates = collect($this->actingAs($cashier)->getJson('/api/daily-plates')->json('dishes'))->keyBy('name');
        $this->assertEquals(40, $plates['Beef']['prepared']);
        $this->assertEquals(3, $plates['Beef']['sold']);
        $this->assertEquals(37, $plates['Beef']['left']);
        $this->assertEquals(37, $this->menu($cashier)['Beef']['balance']);

        $this->sell($cashier, ['Fish' => 20])->assertUnprocessable()
            ->assertJsonPath('errors.lines.0', 'Only 19 Fish plates left today at Kira (Main/Warehouse): cannot sell 20.');

        // Tomorrow starts from nothing again.
        $this->travel(1)->days();
        $this->assertEquals(0, $this->menu($cashier)['Beef']['balance']);

        // Plates are not kitchen stock.
        $manager = User::factory()->create(['role' => User::ROLE_STORE_MANAGER, 'store_id' => $this->kira->id]);
        $names = collect($this->actingAs($manager)->getJson('/api/stock/status')->json('items'))->pluck('item_name');
        $this->assertNotContains('Beef', $names);
    }

    public function test_a_discount_needs_a_note_and_shows_in_the_figures(): void
    {
        $cashier = $this->cashier($this->kira);
        $this->prepare($cashier, ['Beef' => 10]);

        $this->sell($cashier, ['Beef' => 2], ['discount' => 5000])->assertUnprocessable()
            ->assertJsonPath('errors.discount_note.0', 'Say why there is a discount.');
        $this->sell($cashier, ['Beef' => 2], ['discount' => 60000, 'discount_note' => 'x'])->assertUnprocessable();
        $this->sell($cashier, ['Beef' => 2], ['discount' => 5000, 'discount_note' => 'Regular customer'])
            ->assertCreated()->assertJsonPath('total', '45000.00')->assertJsonPath('discount_note', 'Regular customer');

        $summary = $this->actingAs($this->owner)->getJson("/api/sales/summary?store_id={$this->kira->id}")->json();
        $this->assertEquals(45000, $summary['total_revenue']);
        $this->assertEquals(5000, $summary['discounts']);
        $branch = $this->actingAs($this->owner)->getJson("/api/reports/branches/{$this->kira->id}")->json('totals');
        $this->assertEquals(45000, $branch['revenue']);
        $this->assertEquals(5000, $branch['discounts']);
    }

    public function test_a_cashier_allowed_by_the_owner_records_expenses(): void
    {
        $joy = $this->cashier($this->town);
        $this->actingAs($joy)->postJson('/api/expenses', ['amount' => 5000, 'category' => 'Transport', 'note' => 'Boda to market'])
            ->assertForbidden();

        $this->actingAs($this->owner)->patchJson("/api/users/{$joy->id}", ['can_record_expenses' => true])->assertOk();
        $this->actingAs($joy->fresh())->postJson('/api/expenses', ['amount' => 5000, 'category' => 'Transport'])
            ->assertUnprocessable()->assertJsonPath('errors.note.0', 'Say what the money was for.');
        $this->actingAs($joy->fresh())->postJson('/api/expenses', ['amount' => 5000, 'category' => 'Transport', 'note' => 'Boda to market'])
            ->assertCreated()->assertJsonPath('store_id', $this->town->id);
        $this->actingAs($joy->fresh())->postJson('/api/expenses', ['amount' => 3000, 'category' => 'Small purchases', 'note' => 'Matches'])
            ->assertCreated();

        $this->prepare($joy, ['Beef' => 5]);
        $this->sell($joy, ['Beef' => 2, 'Milk Tea' => 1])->assertCreated(); // 23,000 cash

        $day = $this->actingAs($joy)->getJson('/api/reports/my-day')->assertOk()->json();
        $this->assertEquals(23000, $day['total']);
        $this->assertEquals(8000, $day['expenses_total']);
        $this->assertEquals(15000, $day['cash_to_hand_over']);
        $this->assertEquals(2, collect($day['items'])->firstWhere('name', 'Beef')['qty']);

        $town = $this->actingAs($this->owner)->getJson("/api/reports/branches/{$this->town->id}")->json('expenses');
        $this->assertEquals(8000, $town['total']);

        // A manager cancels one, with a reason.
        $manager = User::factory()->create(['role' => User::ROLE_STORE_MANAGER, 'store_id' => $this->town->id]);
        $id = $this->actingAs($manager)->getJson('/api/expenses')->json('data.0.id');
        $this->actingAs($manager)->postJson("/api/expenses/{$id}/void", ['reason' => 'Entered twice'])->assertOk();
        $this->assertEquals(5000, $this->actingAs($joy)->getJson('/api/reports/my-day')->json('expenses_total'));
        $this->assertSame('voided', EditLog::latest('id')->value('action'));
    }

    public function test_each_cashier_sees_only_their_own_day(): void
    {
        $joy = $this->cashier($this->town);
        $ann = $this->cashier($this->town);
        $this->prepare($joy, ['Beef' => 5]);
        $this->sell($joy, ['Beef' => 1])->assertCreated();
        $this->sell($ann, ['Milk Tea' => 2])->assertCreated();

        $this->assertEquals(10000, $this->actingAs($joy)->getJson('/api/reports/my-day')->json('total'));
        $this->assertEquals(6000, $this->actingAs($ann)->getJson('/api/reports/my-day')->json('total'));
        $this->actingAs($joy)->getJson("/api/reports/my-day?user_id={$ann->id}")->assertForbidden();

        $manager = User::factory()->create(['role' => User::ROLE_STORE_MANAGER, 'store_id' => $this->town->id]);
        $this->assertEquals(6000, $this->actingAs($manager)->getJson("/api/reports/my-day?user_id={$ann->id}")->json('total'));
        $this->assertEquals(16000, $this->actingAs($manager)->getJson('/api/reports/my-day?scope=branch')->json('total'));
    }

    public function test_purchases_record_the_price_for_the_ledger(): void
    {
        $procurement = User::factory()->create(['role' => User::ROLE_STOREKEEPER, 'store_id' => $this->kira->id]);
        $sugar = Item::where('name', 'Sugar')->firstOrFail();
        $charcoal = Item::where('name', 'Charcoal')->firstOrFail();
        $this->actingAs($procurement)->postJson('/api/stock/purchase', ['item_id' => $sugar->id, 'qty' => 50, 'unit_cost' => 4200, 'supplier' => 'Owino market'])->assertCreated();
        $this->actingAs($procurement)->postJson('/api/stock/purchase', ['item_id' => $charcoal->id, 'qty' => 2, 'total_cost' => 140000])->assertCreated();
        $this->actingAs($procurement)->postJson('/api/stock/purchase', ['item_id' => $sugar->id, 'qty' => 10])->assertCreated();

        $ledger = $this->actingAs($this->owner)->getJson('/api/purchases')->assertOk()->json();
        $this->assertEquals(210000 + 140000, $ledger['total_spent']);
        $this->assertSame(1, $ledger['without_price']);
        $this->assertEquals(70000, collect($ledger['rows'])->firstWhere('item', 'Charcoal')['unit_cost']);
        $this->assertSame('Owino market', collect($ledger['rows'])->firstWhere('total', 210000)['supplier']);
        $this->assertEquals(210000, collect($ledger['by_category'])->firstWhere('category', 'Food')['total']);

        $this->actingAs($this->cashier($this->town))->getJson('/api/purchases')->assertForbidden();
    }

    public function test_a_receipt_shows_the_sale_and_only_to_its_branch(): void
    {
        $joy = $this->cashier($this->town);
        $this->prepare($joy, ['Beef' => 5]);
        $id = $this->sell($joy, ['Beef' => 2, 'Milk Tea' => 1], ['discount' => 1000, 'discount_note' => 'Regular'])->json('id');

        $receipt = $this->actingAs($joy)->getJson("/api/sales/{$id}/receipt")->assertOk()->json();
        $this->assertSame('Town', $receipt['store']['name']);
        $this->assertSame($joy->name, $receipt['cashier']);
        $this->assertEquals(23000, $receipt['subtotal']);
        $this->assertEquals(22000, $receipt['total']);
        $this->assertSame('Beef', $receipt['lines'][0]['name']);

        $this->actingAs($this->cashier($this->lugogo))->getJson("/api/sales/{$id}/receipt")->assertForbidden();
        $this->actingAs($this->owner)->getJson("/api/sales/{$id}/receipt")->assertOk();
    }
}
