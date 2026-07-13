<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\HasMany;

#[Fillable(['name', 'unit', 'category', 'is_drink', 'is_active'])]
class Item extends Model
{
    use HasFactory;

    protected function casts(): array
    {
        return [
            'is_drink' => 'boolean',
            'is_active' => 'boolean',
        ];
    }

    public function storeSettings(): HasMany
    {
        return $this->hasMany(ItemStoreSetting::class);
    }

    public function stockMovements(): HasMany
    {
        return $this->hasMany(StockMovement::class);
    }
}
