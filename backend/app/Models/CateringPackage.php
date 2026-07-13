<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\HasMany;

#[Fillable(['name', 'price_per_plate', 'description', 'is_active'])]
class CateringPackage extends Model
{
    use HasFactory;

    protected function casts(): array
    {
        return [
            'price_per_plate' => 'decimal:2',
            'is_active' => 'boolean',
        ];
    }

    public function orders(): HasMany
    {
        return $this->hasMany(CateringOrder::class);
    }
}
