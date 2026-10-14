<?php

namespace Tests\Feature;

use App\Models\Customer;
use App\Models\Item;
use App\Models\Store;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * The app shows each list in one go and never asks for a second page, so a
 * list that stops at Laravel's default of 15 rows hides everything after
 * the fifteenth item, user or customer. These guard that.
 */
class ListSizeTest extends TestCase
{
    use RefreshDatabase;

    private function admin(): User
    {
        return User::factory()->create(['role' => User::ROLE_ADMIN, 'store_id' => null]);
    }

    public function test_every_item_is_returned_not_just_the_first_fifteen(): void
    {
        Item::factory()->count(40)->create();

        $response = $this->actingAs($this->admin())->getJson('/api/items');

        $response->assertOk();
        $this->assertCount(40, $response->json('data'));
    }

    public function test_every_user_branch_and_customer_is_returned(): void
    {
        $admin = $this->admin();
        Store::factory()->count(20)->create();
        User::factory()->count(24)->create(['role' => User::ROLE_CASHIER, 'store_id' => Store::first()->id]);
        Customer::factory()->count(30)->create();

        $this->assertCount(20, $this->actingAs($admin)->getJson('/api/stores')->json('data'));
        $this->assertGreaterThan(15, User::count());
        $this->assertCount(User::count(), $this->actingAs($admin)->getJson('/api/users')->json('data'));
        $this->assertCount(30, $this->actingAs($admin)->getJson('/api/customers')->json('data'));
    }

    public function test_a_page_size_can_be_asked_for_and_is_capped(): void
    {
        Item::factory()->count(12)->create();
        $admin = $this->admin();

        $this->assertCount(5, $this->actingAs($admin)->getJson('/api/items?per_page=5')->json('data'));
        $this->assertSame(500, $this->actingAs($admin)->getJson('/api/items?per_page=99999')->json('per_page'));
    }
}
