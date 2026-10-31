<?php

namespace Tests\Feature;

use App\Models\Customer;
use App\Models\EditLog;
use App\Models\PlatePrice;
use App\Models\Store;
use App\Models\User;
use App\Services\LedgerService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * Each branch has its own customers, and staff are warned before an account
 * runs out.
 */
class BranchCustomersTest extends TestCase
{
    use RefreshDatabase;

    private User $owner;

    private Store $town;

    private Store $lugogo;

    private User $townCashier;

    private User $lugogoCashier;

    protected function setUp(): void
    {
        parent::setUp();
        $this->owner = User::factory()->create(['role' => User::ROLE_ADMIN, 'store_id' => null]);
        Store::factory()->create(['name' => 'Kira', 'is_main' => true]);
        $this->town = Store::factory()->create(['name' => 'Town']);
        $this->lugogo = Store::factory()->create(['name' => 'Lugogo']);
        $this->townCashier = User::factory()->create(['role' => User::ROLE_CASHIER, 'store_id' => $this->town->id]);
        $this->lugogoCashier = User::factory()->create(['role' => User::ROLE_CASHIER, 'store_id' => $this->lugogo->id]);
        PlatePrice::create(['store_id' => null, 'price' => 25000, 'effective_from' => now()->toDateString(), 'is_active' => true]);
    }

    private function plateSale(User $cashier, Customer $customer, int $plates = 1)
    {
        return $this->actingAs($cashier)->postJson('/api/sales', [
            'payment_method' => 'account', 'customer_id' => $customer->id,
            'lines' => [['item_type' => 'plate', 'qty' => $plates]],
        ]);
    }

    public function test_a_branch_adds_its_own_customers_and_only_sees_its_own(): void
    {
        $id = $this->actingAs($this->townCashier)->postJson('/api/customers', [
            'name' => 'Town Regular', 'phone' => '0700000001', 'account_type' => 'prepaid', 'store_id' => $this->lugogo->id,
        ])->assertCreated()->assertJsonPath('store.name', 'Town')->json('id');
        $this->assertSame($this->town->id, Customer::find($id)->store_id, 'staff cannot add to another branch');

        $legacy = Customer::factory()->create(['name' => 'Old Account', 'store_id' => null]);
        Customer::factory()->create(['name' => 'Lugogo Regular', 'store_id' => $this->lugogo->id]);

        $names = collect($this->actingAs($this->townCashier)->getJson('/api/customers')->json('data'))->pluck('name')->all();
        $this->assertEqualsCanonicalizing(['Town Regular', 'Old Account'], $names);

        $this->assertCount(3, $this->actingAs($this->owner)->getJson('/api/customers')->json('data'));
        $this->assertSame(['Lugogo Regular'], collect($this->actingAs($this->owner)->getJson('/api/customers?store_id='.$this->lugogo->id)->json('data'))->pluck('name')->all());

        $this->actingAs($this->lugogoCashier)->getJson("/api/customers/{$id}/statement")->assertForbidden();
        $this->actingAs($this->lugogoCashier)->postJson("/api/customers/{$id}/deposit", ['amount' => 1000])->assertForbidden();
        $this->actingAs($this->lugogoCashier)->getJson("/api/customers/{$legacy->id}")->assertOk();
    }

    public function test_a_customer_is_charged_only_at_their_branch(): void
    {
        $customer = Customer::factory()->create(['name' => 'Jane', 'store_id' => $this->town->id]);
        app(LedgerService::class)->deposit($customer, 100000, $this->owner->id);

        $this->plateSale($this->lugogoCashier, $customer)->assertUnprocessable()
            ->assertJsonPath('errors.customer_id.0', 'Jane is a customer of Town. Charge their account at Town, or ask the owner to move it.');
        $this->plateSale($this->townCashier, $customer)->assertCreated();
    }

    public function test_staff_are_warned_when_credit_is_nearly_used_and_stopped_at_the_limit(): void
    {
        $customer = Customer::factory()->credit(100000)->create(['name' => 'Jane', 'store_id' => $this->town->id]);

        $this->plateSale($this->townCashier, $customer, 3)->assertCreated()
            ->assertJsonPath('customer_account.status', 'ok')
            ->assertJsonPath('customer_account.available', 25000);

        // 75,000 used of 100,000 = 75%: one more plate takes it to 100%.
        $this->plateSale($this->townCashier, $customer, 1)->assertCreated()
            ->assertJsonPath('customer_account.status', 'blocked')
            ->assertJsonPath('customer_account.warning', 'Jane has reached the credit limit. Collect a payment before charging more.');

        $this->plateSale($this->townCashier, $customer, 1)->assertUnprocessable();

        $this->actingAs($this->townCashier)->getJson("/api/customers/{$customer->id}/balance")
            ->assertJsonPath('credit_used_pct', 100)
            ->assertJsonPath('status', 'blocked');
    }

    public function test_eighty_percent_of_the_limit_is_a_warning(): void
    {
        $customer = Customer::factory()->credit(200000)->create(['name' => 'Jane', 'store_id' => $this->town->id]);
        $this->plateSale($this->townCashier, $customer, 7)->assertCreated()   // 175,000 = 87.5%
            ->assertJsonPath('customer_account.status', 'low')
            ->assertJsonPath('customer_account.warning', 'Jane has used 88% of the credit limit (UGX 200,000): UGX 25,000 left.');

        $dashboard = $this->actingAs($this->owner)->getJson('/api/reports/dashboard')->json('accounts_needing_attention');
        $this->assertSame('Jane', $dashboard[0]['name']);
        $this->assertSame('low', $dashboard[0]['status']);
        $this->assertSame('Town', $dashboard[0]['store_name']);
    }

    public function test_a_prepaid_balance_below_a_plate_is_a_warning(): void
    {
        $customer = Customer::factory()->create(['name' => 'Ali', 'store_id' => $this->town->id]);
        app(LedgerService::class)->deposit($customer, 60000, $this->owner->id);

        $this->plateSale($this->townCashier, $customer, 2)->assertCreated()
            ->assertJsonPath('customer_account.status', 'low')
            ->assertJsonPath('customer_account.warning', 'Ali has only UGX 10,000 left, less than a plate.');
    }

    public function test_only_the_owner_sets_credit_limits_and_every_edit_has_a_reason(): void
    {
        $customer = Customer::factory()->credit(50000)->create(['name' => 'Jane', 'store_id' => $this->town->id]);
        $manager = User::factory()->create(['role' => User::ROLE_STORE_MANAGER, 'store_id' => $this->town->id]);

        $this->actingAs($manager)->patchJson("/api/customers/{$customer->id}", ['credit_limit' => 500000, 'reason' => 'Good customer'])->assertForbidden();
        $this->actingAs($manager)->patchJson("/api/customers/{$customer->id}", ['phone' => '0711111111'])
            ->assertUnprocessable()->assertJsonPath('errors.reason.0', 'Say why this account is changing.');
        $this->actingAs($manager)->patchJson("/api/customers/{$customer->id}", ['phone' => '0711111111', 'reason' => 'New number'])->assertOk();

        $this->actingAs($this->owner)->patchJson("/api/customers/{$customer->id}", [
            'credit_limit' => 150000, 'store_id' => $this->lugogo->id, 'reason' => 'Moved to Lugogo, pays on time',
        ])->assertOk()->assertJsonPath('store.name', 'Lugogo');

        $log = EditLog::latest('id')->first();
        $this->assertEquals(['from' => 50000, 'to' => 150000], $log->changes['credit_limit']);
        $this->assertEquals(['from' => 'Town', 'to' => 'Lugogo'], $log->changes['store_id']);
    }

    public function test_a_wrong_deposit_is_corrected_with_a_reason(): void
    {
        $customer = Customer::factory()->create(['store_id' => $this->town->id]);
        app(LedgerService::class)->deposit($customer, 50000, $this->owner->id);
        $manager = User::factory()->create(['role' => User::ROLE_STORE_MANAGER, 'store_id' => $this->town->id]);

        $this->actingAs($manager)->postJson("/api/customers/{$customer->id}/adjustment", ['amount' => -45000, 'reason' => 'Deposit was 5,000 not 50,000'])
            ->assertCreated()->assertJsonPath('balance', 5000);
        $this->actingAs($this->townCashier)->postJson("/api/customers/{$customer->id}/adjustment", ['amount' => 1000, 'reason' => 'x'])->assertForbidden();

        $this->assertSame('balance_corrected', EditLog::sole()->action);
    }
}
