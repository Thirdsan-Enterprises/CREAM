<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/** Money a branch paid out of its takings: transport, small purchases. */
#[Fillable(['store_id', 'amount', 'category', 'note', 'paid_from', 'recorded_by', 'spent_at', 'voided_at', 'voided_by', 'void_reason'])]
class Expense extends Model
{
    public const CATEGORIES = ['Transport', 'Small purchases', 'Staff allowance', 'Repairs', 'Other'];

    protected function casts(): array
    {
        return [
            'amount' => 'decimal:2',
            'spent_at' => 'datetime',
            'voided_at' => 'datetime',
        ];
    }

    public function scopeCounted(Builder $query): void
    {
        $query->whereNull('voided_at');
    }

    public function store(): BelongsTo
    {
        return $this->belongsTo(Store::class);
    }

    public function recordedBy(): BelongsTo
    {
        return $this->belongsTo(User::class, 'recorded_by');
    }

    public function voidedBy(): BelongsTo
    {
        return $this->belongsTo(User::class, 'voided_by');
    }
}
