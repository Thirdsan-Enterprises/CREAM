<?php

namespace Tests\Feature;

use App\Models\Customer;
use App\Models\Store;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class CustomerTest extends TestCase
{
    use RefreshDatabase;

    public function test_cashier_can_create_a_customer_account(): void
    {
        $store = Store::factory()->create();
        $cashier = User::factory()->create(['role' => User::ROLE_CASHIER, 'store_id' => $store->id]);

        $response = $this->actingAs($cashier)->postJson('/api/customers', [
            'name' => 'John Doe',
            'phone' => '0700999888',
            'account_type' => 'prepaid',
        ]);

        $response->assertCreated();
        $this->assertDatabaseHas('customers', ['phone' => '0700999888', 'account_type' => 'prepaid']);
    }

    public function test_search_finds_customer_by_name_or_phone(): void
    {
        $store = Store::factory()->create();
        $cashier = User::factory()->create(['role' => User::ROLE_CASHIER, 'store_id' => $store->id]);
        Customer::factory()->create(['name' => 'Alice Wanjiru', 'phone' => '0711111111']);
        Customer::factory()->create(['name' => 'Bob Kato', 'phone' => '0722222222']);

        $response = $this->actingAs($cashier)->getJson('/api/customers?search=Alice');

        $response->assertOk();
        $this->assertCount(1, $response->json('data'));
        $this->assertEquals('Alice Wanjiru', $response->json('data.0.name'));
    }

    public function test_deposit_increases_prepaid_balance_and_appears_in_statement(): void
    {
        $store = Store::factory()->create();
        $cashier = User::factory()->create(['role' => User::ROLE_CASHIER, 'store_id' => $store->id]);
        $customer = Customer::factory()->create(['account_type' => Customer::TYPE_PREPAID]);

        $response = $this->actingAs($cashier)->postJson("/api/customers/{$customer->id}/deposit", [
            'amount' => 50000,
        ]);

        $response->assertCreated()->assertJson(['balance' => 50000]);

        $balance = $this->actingAs($cashier)->getJson("/api/customers/{$customer->id}/balance");
        $balance->assertOk()->assertJson(['balance' => 50000]);

        $statement = $this->actingAs($cashier)->getJson("/api/customers/{$customer->id}/statement");
        $statement->assertOk();
        $this->assertCount(1, $statement->json('entries.data'));
    }

    public function test_storekeeper_cannot_manage_customers(): void
    {
        $store = Store::factory()->create(['is_main' => true]);
        $storekeeper = User::factory()->create(['role' => User::ROLE_STOREKEEPER, 'store_id' => $store->id]);

        $this->actingAs($storekeeper)->getJson('/api/customers')->assertStatus(403);
    }
}
