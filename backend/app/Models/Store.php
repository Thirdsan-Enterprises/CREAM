<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\HasMany;

#[Fillable(['name', 'code', 'is_main', 'sells', 'address', 'phone', 'is_active'])]
class Store extends Model
{
    use HasFactory;

    protected $attributes = ['sells' => true];

    protected function casts(): array
    {
        return [
            'is_main' => 'boolean',
            'sells' => 'boolean',
            'is_active' => 'boolean',
        ];
    }

    /** The procurement unit: buys for everyone and sends to the branches. */
    public static function main(): ?self
    {
        return self::where('is_main', true)->first();
    }

    public function users(): HasMany
    {
        return $this->hasMany(User::class);
    }

    public function stockMovements(): HasMany
    {
        return $this->hasMany(StockMovement::class);
    }

    public function itemStoreSettings(): HasMany
    {
        return $this->hasMany(ItemStoreSetting::class);
    }
}
