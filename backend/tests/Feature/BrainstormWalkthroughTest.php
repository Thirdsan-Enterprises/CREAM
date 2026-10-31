<?php

namespace Tests\Feature;

use App\Models\Store;
use Carbon\Carbon;
use Database\Seeders\DatabaseSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * Everything agreed in the client brainstorm, end to end through the real
 * API with the seeded data, in the order a real day would happen:
 *
 *  - Town's plate costs 15,000; tea and eggs are sold on their own.
 *  - The procurement unit has its own login, buys eggs and answers Town's
 *    request for them; Town confirms the delivery.
 *  - Town adds its own customer; staff are warned as the credit runs out.
 *  - A mistaken sale is voided with a reason; the owner sees every change
 *    and why; the branch report adds up.
 */
class BrainstormWalkthroughTest extends TestCase
{
    use RefreshDatabase;

    private ?string $token = null;

    private function login(string $phone, string $password): string
    {
        $this->app['auth']->shouldUse('web');

        return $this->postJson('/api/auth/login', ['phone' => $phone, 'password' => $password])->assertOk()->json('token');
    }

    private function actAs(string $token): void
    {
        $this->token = $token;
        $this->app['auth']->forgetGuards();
    }

    private function api(string $method, string $uri, array $data = [])
    {
        return $this->withToken($this->token)->json($method, $uri, $data);
    }

    public function test_a_day_with_everything_from_the_brainstorm(): void
    {
        Carbon::setTestNow(Carbon::parse('2026-11-02 06:00:00', 'UTC')); // 9am in Kampala
        $this->seed(DatabaseSeeder::class);
        $kira = Store::where('is_main', true)->firstOrFail();
        $town = Store::where('code', 'TOWN')->firstOrFail();

        // The owner sets up: Town plate at 15,000, tea and eggs on the menu,
        // a procurement login and a Town manager and cashier.
        $owner = $this->login('0700000000', 'password');
        $this->actAs($owner);
        $this->api('PATCH', '/api/plate-price', ['store_id' => $town->id, 'price' => 15000, 'reason' => 'Town customers pay less'])->assertCreated();
        $tea = $this->api('POST', '/api/menu-items', ['name' => 'Tea', 'unit' => 'cup', 'category' => 'Breakfast', 'price' => 1000, 'tracks_stock' => false])->assertCreated()->json('item.id');
        $egg = $this->api('POST', '/api/menu-items', ['name' => 'Boiled egg', 'unit' => 'piece', 'category' => 'Breakfast', 'price' => 1500, 'safety_stock' => 6])->assertCreated()->json('item.id');
        $this->api('POST', '/api/users', ['name' => 'Tom', 'phone' => '0772000001', 'password' => 'procurement1', 'role' => 'storekeeper'])
            ->assertCreated()->assertJsonPath('store.id', $kira->id);
        $this->api('POST', '/api/users', ['name' => 'Grace', 'phone' => '0772000002', 'password' => 'town-manager', 'role' => 'store_manager', 'store_id' => $town->id])->assertCreated();
        $this->api('POST', '/api/users', ['name' => 'Sarah', 'phone' => '0772000003', 'password' => 'town-cashier', 'role' => 'cashier', 'store_id' => $town->id])->assertCreated();

        // Procurement signs in and buys eggs at the procurement unit.
        $procurement = $this->login('0772000001', 'procurement1');
        $this->actAs($procurement);
        $this->api('POST', '/api/stock/purchase', ['item_id' => $egg, 'qty' => 60])->assertCreated();

        // Town is out of eggs and asks for them (the egg shows as Re-Order).
        $manager = $this->login('0772000002', 'town-manager');
        $this->actAs($manager);
        $eggStatus = collect($this->api('GET', '/api/stock/status')->json('items'))->firstWhere('item_id', $egg);
        $this->assertSame('Re-Order', $eggStatus['status']);
        $requestId = $this->api('POST', '/api/stock-requests', ['items' => [['item_id' => $egg, 'qty' => 30]], 'note' => 'For breakfast'])->assertCreated()->json('id');

        // Procurement sends them; Town confirms on arrival.
        $this->actAs($procurement);
        $this->api('GET', '/api/stock-requests?status=open')->assertJsonPath('data.0.items.0.available_at_procurement', 60);
        $transferId = $this->api('POST', "/api/stock-requests/{$requestId}/send")->assertOk()->json('stock_transfer_id');
        $this->actAs($manager);
        $lines = $this->api('GET', "/api/transfers/{$transferId}")->json('items');
        $this->api('POST', "/api/transfers/{$transferId}/confirm", [
            'items' => array_map(fn ($l) => ['stock_transfer_item_id' => $l['id'], 'qty_received' => $l['qty_dispatched']], $lines),
        ])->assertOk();

        // Breakfast: tea and an egg on their own, then lunch at Town's price.
        $cashier = $this->login('0772000003', 'town-cashier');
        $this->actAs($cashier);
        $menu = collect($this->api('GET', '/api/menu')->json())->keyBy('item.name');
        $this->assertNull($menu['Tea']['balance'], 'tea is made to order');
        $this->assertEquals(30, $menu['Boiled egg']['balance']);
        $this->api('POST', '/api/sales', ['payment_method' => 'cash', 'lines' => [
            ['item_type' => 'item', 'item_id' => $tea, 'qty' => 2],
            ['item_type' => 'item', 'item_id' => $egg, 'qty' => 2],
        ]])->assertCreated()->assertJsonPath('total', '5000.00');
        $mistake = $this->api('POST', '/api/sales', ['payment_method' => 'momo', 'lines' => [['item_type' => 'plate', 'qty' => 3]]])
            ->assertCreated()->assertJsonPath('total', '45000.00')->json('id');

        // Town's own customer, on credit the owner sets.
        $jane = $this->api('POST', '/api/customers', ['name' => 'Jane', 'phone' => '0772999999', 'account_type' => 'credit'])
            ->assertCreated()->assertJsonPath('store.id', $town->id)->json('id');
        $this->actAs($owner);
        $this->api('PATCH', "/api/customers/{$jane}", ['credit_limit' => 50000, 'reason' => 'Works next door, pays monthly'])->assertOk();
        $this->actAs($cashier);
        $this->api('POST', '/api/sales', ['payment_method' => 'account', 'customer_id' => $jane, 'lines' => [['item_type' => 'plate', 'qty' => 2]]])
            ->assertCreated()->assertJsonPath('customer_account.status', 'ok');
        $this->api('POST', '/api/sales', ['payment_method' => 'account', 'customer_id' => $jane, 'lines' => [['item_type' => 'plate', 'qty' => 1]]])
            ->assertCreated()->assertJsonPath('customer_account.status', 'low')
            ->assertJsonPath('customer_account.warning', 'Jane has used 90% of the credit limit (UGX 50,000): UGX 5,000 left.');

        // The manager voids the plates rung up by mistake.
        $this->actAs($manager);
        $this->api('POST', "/api/sales/{$mistake}/void", ['reason' => 'Rang 3 plates instead of 3 sodas'])->assertOk();

        // The owner's view: today's figures leave out the voided sale.
        $this->actAs($owner);
        $summary = $this->api('GET', "/api/sales/summary?store_id={$town->id}&from=2026-11-02&to=2026-11-02")->json();
        $this->assertEquals(5000 + 45000, $summary['total_revenue']);
        $this->assertEquals(45000, $summary['plate_revenue']);
        $this->assertEquals(5000, $summary['item_revenue']);

        $branch = $this->api('GET', "/api/reports/branches/{$town->id}?from=2026-11-02&to=2026-11-02")->assertOk()->json();
        $this->assertEquals(50000, $branch['totals']['revenue']);
        $this->assertSame(1, $branch['transfers']['received']);
        $this->assertEqualsCanonicalizing(['Tea', 'Boiled egg'], collect($branch['menu_items'])->pluck('name')->all());

        $dashboard = $this->api('GET', '/api/reports/dashboard')->json();
        $this->assertSame('Jane', $dashboard['accounts_needing_attention'][0]['name']);
        $this->assertSame(0, $dashboard['open_stock_requests']);

        // And every change after the fact, with who and why.
        $changes = collect($this->api('GET', '/api/edit-logs')->json('data'));
        $this->assertEqualsCanonicalizing(
            ['Plate price at Town', 'Customer: Jane', "Sale #{$mistake}"],
            $changes->pluck('subject_label')->all(),
        );
        $this->assertSame('Rang 3 plates instead of 3 sodas', $changes->firstWhere('action', 'voided')['reason']);
        $this->assertSame('Grace', $changes->firstWhere('action', 'voided')['user']['name']);
    }
}
