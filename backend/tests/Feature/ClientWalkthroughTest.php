<?php

namespace Tests\Feature;

use App\Models\Store;
use Carbon\Carbon;
use Database\Seeders\DatabaseSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * The journey in the user manual, step by step, through the real API as the
 * real seeded accounts would use it. If this test passes, every step the
 * manual tells the client to take works. If you change the manual, change
 * this test with it.
 */
class ClientWalkthroughTest extends TestCase
{
    use RefreshDatabase;

    private ?string $token = null;

    /** Sign in through the real login endpoint and return the token. */
    private function login(string $phone, string $password): string
    {
        // A real request starts a fresh process; in a test the app is shared,
        // so undo the default guard that the previous authenticated call set.
        $this->app['auth']->shouldUse('web');
        $response = $this->postJson('/api/auth/login', ['phone' => $phone, 'password' => $password]);
        $response->assertOk();

        return $response->json('token');
    }

    /** Carry on as the person who holds this token. */
    private function actAs(string $token): void
    {
        $this->token = $token;
        $this->app['auth']->forgetGuards();
    }

    private function api(string $method, string $uri, array $data = [])
    {
        return $this->withToken($this->token)->json($method, $uri, $data);
    }

    private function stockOf(int $storeId, string $itemName): ?array
    {
        $rows = $this->api('GET', "/api/stock/status?store_id={$storeId}")->json('items');

        return collect($rows)->firstWhere('item_name', $itemName);
    }

    public function test_the_whole_manual_from_first_login_to_dashboard(): void
    {
        Carbon::setTestNow(Carbon::parse('2026-10-13 09:00:00', 'UTC'));
        $this->seed(DatabaseSeeder::class);

        $kira = Store::where('is_main', true)->firstOrFail();
        $lugogo = Store::where('code', 'LUGOGO')->firstOrFail();

        // 1. The owner signs in with the seeded account.
        $owner = $this->login('0700000000', 'password');
        $this->actAs($owner);
        $this->assertSame('admin', $this->api('GET', '/api/auth/me')->json('role'));

        // 2. The owner sets up staff: a Lugogo manager and a Lugogo cashier.
        $this->api('POST', '/api/users', [
            'name' => 'Grace', 'phone' => '0771000001', 'password' => 'lugogo-manager',
            'role' => 'store_manager', 'store_id' => $lugogo->id,
        ])->assertCreated();
        $this->api('POST', '/api/users', [
            'name' => 'Sarah', 'phone' => '0771000002', 'password' => 'lugogo-cashier',
            'role' => 'cashier', 'store_id' => $lugogo->id,
        ])->assertCreated();
        $manager = $this->login('0771000001', 'lugogo-manager');
        $cashier = $this->login('0771000002', 'lugogo-cashier');

        // 3. Before anything is stocked, everything is at 0 and needs re-ordering.
        $rice = $this->stockOf($kira->id, 'Rice');
        $this->assertEquals(0, $rice['balance']);
        $this->assertSame('Re-Order', $rice['status']);

        // 4. Stocking an item that already exists (Stocking > Purchase, at Kira).
        $this->api('POST', '/api/stock/purchase', [
            'store_id' => $kira->id, 'item_id' => $rice['item_id'], 'qty' => 100, 'note' => 'Market',
        ])->assertCreated();
        $rice = $this->stockOf($kira->id, 'Rice');
        $this->assertEquals(100, $rice['balance']);
        $this->assertSame('Stock Sufficient', $rice['status']);

        // 5. Adding a brand-new item and stocking it. It must show up at every
        //    branch straight away, or there is nothing to stock, transfer or sell.
        $created = $this->api('POST', '/api/items', ['name' => 'Sugar', 'unit' => 'kg']);
        $created->assertCreated();
        $sugarId = $created->json('id');

        foreach (Store::all() as $store) {
            $row = $this->stockOf($store->id, 'Sugar');
            $this->assertNotNull($row, "A new item must appear in {$store->name}'s stock list");
            $this->assertEquals(0, $row['balance']);
        }

        $this->api('POST', '/api/stock/purchase', [
            'store_id' => $kira->id, 'item_id' => $sugarId, 'qty' => 50,
        ])->assertCreated();
        $this->assertEquals(50, $this->stockOf($kira->id, 'Sugar')['balance']);

        // 6. Dispatch to Lugogo (Stocking > Transfer). Kira's balance drops at once.
        $this->api('POST', '/api/transfers', [
            'to_store_id' => $lugogo->id,
            'items' => [['item_id' => $sugarId, 'qty' => 20], ['item_id' => $rice['item_id'], 'qty' => 40]],
        ])->assertCreated();
        $this->assertEquals(30, $this->stockOf($kira->id, 'Sugar')['balance']);
        $this->assertEquals(0, $this->stockOf($lugogo->id, 'Sugar')['balance'], 'Not Lugogo\'s until confirmed');

        // 7. The Lugogo manager confirms what actually arrived (2 kg of rice short).
        $this->actAs($manager);
        $incoming = $this->api('GET', '/api/transfers?status=dispatched')->json('data');
        $this->assertCount(1, $incoming);
        $lines = collect($incoming[0]['items']);
        $this->api('POST', "/api/transfers/{$incoming[0]['id']}/confirm", ['items' => [
            ['stock_transfer_item_id' => $lines->firstWhere('item_id', $sugarId)['id'], 'qty_received' => 20],
            ['stock_transfer_item_id' => $lines->firstWhere('item_id', $rice['item_id'])['id'], 'qty_received' => 38],
        ]])->assertOk();
        $this->assertEquals(20, $this->stockOf($lugogo->id, 'Sugar')['balance']);
        $this->assertEquals(38, $this->stockOf($lugogo->id, 'Rice')['balance']);
        $this->assertSame('discrepancy', $this->api('GET', "/api/transfers/{$incoming[0]['id']}")->json('status'));

        // 8. Drinks are bought at the branch itself, by its manager.
        $soda = collect($this->api('GET', '/api/drinks')->json())->first(fn ($d) => $d['item']['name'] === 'Soda');
        $this->api('POST', '/api/stock/purchase', ['item_id' => $soda['item']['id'], 'qty' => 24])->assertCreated();
        $sodaRow = $this->stockOf($lugogo->id, 'Soda');
        $this->assertEquals(24, $sodaRow['balance']);
        $this->assertSame('Stock Sufficient', $sodaRow['status']);

        // ...but food cannot be bought at a branch.
        $this->api('POST', '/api/stock/purchase', ['item_id' => $rice['item_id'], 'qty' => 5])
            ->assertUnprocessable();

        // 9. The manager records what the kitchen used today.
        $this->api('POST', '/api/stock/consumption', ['item_id' => $rice['item_id'], 'qty' => 8])->assertCreated();
        $this->assertEquals(30, $this->stockOf($lugogo->id, 'Rice')['balance']);

        // 10. The cashier sells: 2 plates + 2 sodas for cash.
        $this->actAs($cashier);
        $price = $this->api('GET', '/api/plate-price')->json('price');
        $this->assertEquals(25000, $price);
        $sale = $this->api('POST', '/api/sales', [
            'payment_method' => 'cash',
            'lines' => [
                ['item_type' => 'plate', 'qty' => 2],
                ['item_type' => 'drink', 'item_id' => $soda['item']['id'], 'qty' => 2],
            ],
        ]);
        $sale->assertCreated();
        $this->assertEquals(54000, $sale->json('total'));
        $this->assertEquals(22, $this->stockOf($lugogo->id, 'Soda')['balance'], 'Selling drinks deducts stock');

        // 11. A prepaid customer tops up and pays by account.
        $customer = $this->api('POST', '/api/customers', [
            'name' => 'Kampala Law Chambers', 'phone' => '0772555000', 'account_type' => 'prepaid',
        ]);
        $customer->assertCreated();
        $this->api('POST', "/api/customers/{$customer->json('id')}/deposit", ['amount' => 100000])->assertCreated();
        $this->api('POST', '/api/sales', [
            'payment_method' => 'account', 'customer_id' => $customer->json('id'),
            'lines' => [['item_type' => 'plate', 'qty' => 3]],
        ])->assertCreated();
        $this->assertEquals(25000, $this->api('GET', "/api/customers/{$customer->json('id')}/balance")->json('balance'));

        // ...and cannot overspend the prepaid balance.
        $this->api('POST', '/api/sales', [
            'payment_method' => 'account', 'customer_id' => $customer->json('id'),
            'lines' => [['item_type' => 'plate', 'qty' => 2]],
        ])->assertUnprocessable();

        // 12. The cashier's own day.
        $day = $this->api('GET', '/api/sales/summary?from=2026-10-13&to=2026-10-13');
        $this->assertEquals(54000 + 75000, $day->json('total_revenue'));
        $this->assertEquals(5, $day->json('plates_sold'));

        // 13. The owner checks the dashboard and the Branches screen.
        $this->actAs($owner);
        $dashboard = $this->api('GET', '/api/reports/dashboard');
        $this->assertEquals(129000, $dashboard->json('sales_total_today'));
        $this->assertEquals(5, $dashboard->json('plates_sold_today'));
        $alerts = collect($dashboard->json('low_stock_alerts'));
        $this->assertFalse(
            $alerts->contains(fn ($a) => $a['store_id'] === $kira->id && $a['item_name'] === 'Sugar'),
            'Sugar is stocked at Kira, so it is not an alert there',
        );
        $this->assertTrue(
            $alerts->contains(fn ($a) => $a['store_id'] === $lugogo->id && $a['item_name'] === 'Matooke'),
            'Matooke was never stocked at Lugogo, so it still needs re-ordering',
        );

        $branches = collect($this->api('GET', '/api/reports/branches?from=2026-10-13&to=2026-10-13')->json('branches'))
            ->keyBy('store_name');
        $this->assertEquals(129000, $branches['Lugogo']['revenue']);
        $this->assertEquals(0, $branches['Town']['revenue']);

        // 14. Adding a new branch gives it the full item list at once.
        $ntinda = $this->api('POST', '/api/stores', ['name' => 'Ntinda', 'code' => 'NTINDA']);
        $ntinda->assertCreated();
        $this->assertNotNull($this->stockOf($ntinda->json('id'), 'Rice'), 'A new branch lists every item');
        $this->assertNotNull($this->stockOf($ntinda->json('id'), 'Soda'));
        $this->assertNotNull($this->stockOf($ntinda->json('id'), 'Sugar'));

        Carbon::setTestNow();
    }
}
