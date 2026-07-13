<?php

namespace Tests\Feature;

use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class AuthTest extends TestCase
{
    use RefreshDatabase;

    public function test_user_can_login_with_phone_and_password(): void
    {
        $user = User::factory()->create([
            'phone' => '0700111222',
            'password' => bcrypt('secret123'),
            'role' => User::ROLE_CASHIER,
        ]);

        $response = $this->postJson('/api/auth/login', [
            'phone' => '0700111222',
            'password' => 'secret123',
        ]);

        $response->assertOk()->assertJsonStructure(['token', 'user']);
    }

    public function test_login_fails_with_wrong_password(): void
    {
        User::factory()->create(['phone' => '0700111222']);

        $response = $this->postJson('/api/auth/login', [
            'phone' => '0700111222',
            'password' => 'wrong',
        ]);

        $response->assertStatus(422);
    }

    public function test_inactive_user_cannot_login(): void
    {
        User::factory()->create([
            'phone' => '0700111222',
            'password' => bcrypt('secret123'),
            'is_active' => false,
        ]);

        $response = $this->postJson('/api/auth/login', [
            'phone' => '0700111222',
            'password' => 'secret123',
        ]);

        $response->assertStatus(422);
    }
}
