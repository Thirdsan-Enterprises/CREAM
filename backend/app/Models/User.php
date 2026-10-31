<?php

namespace App\Models;

use Database\Factories\UserFactory;
use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Attributes\Hidden;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Foundation\Auth\User as Authenticatable;
use Illuminate\Notifications\Notifiable;
use Laravel\Sanctum\HasApiTokens;

#[Fillable(['name', 'phone', 'email', 'password', 'role', 'store_id', 'is_active'])]
#[Hidden(['password', 'remember_token'])]
class User extends Authenticatable
{
    /** @use HasFactory<UserFactory> */
    use HasApiTokens, HasFactory, Notifiable;

    public const ROLE_ADMIN = 'admin';

    public const ROLE_STORE_MANAGER = 'store_manager';

    public const ROLE_CASHIER = 'cashier';

    public const ROLE_STOREKEEPER = 'storekeeper';

    protected function casts(): array
    {
        return [
            'email_verified_at' => 'datetime',
            'password' => 'hashed',
            'is_active' => 'boolean',
        ];
    }

    public function store(): BelongsTo
    {
        return $this->belongsTo(Store::class);
    }

    public function isAdmin(): bool
    {
        return $this->role === self::ROLE_ADMIN;
    }

    /**
     * Works for the procurement unit: buys stock and sends it to branches.
     * That is the storekeeper ("Procurement" in the app) and the manager of
     * the main store. The owner can do all of it too.
     */
    public function isProcurement(): bool
    {
        if ($this->role === self::ROLE_STOREKEEPER) {
            return true;
        }

        return $this->role === self::ROLE_STORE_MANAGER && (bool) $this->store?->is_main;
    }
}
