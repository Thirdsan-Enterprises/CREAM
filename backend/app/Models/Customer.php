<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

#[Fillable(['store_id', 'name', 'phone', 'account_type', 'credit_limit', 'is_active', 'created_by'])]
class Customer extends Model
{
    use HasFactory;

    public const TYPE_PREPAID = 'prepaid';

    public const TYPE_CREDIT = 'credit';

    public const TYPE_LPO = 'lpo';

    protected function casts(): array
    {
        return [
            'credit_limit' => 'decimal:2',
            'is_active' => 'boolean',
        ];
    }

    public function store(): BelongsTo
    {
        return $this->belongsTo(Store::class);
    }

    /**
     * Staff may serve a customer of their own branch, or one with no branch
     * (accounts opened before customers belonged to a branch). The owner may
     * serve anyone.
     */
    public function isServedBy(User $user): bool
    {
        return $user->isAdmin() || $this->store_id === null || $this->store_id === $user->store_id;
    }

    public function createdBy(): BelongsTo
    {
        return $this->belongsTo(User::class, 'created_by');
    }

    public function ledgerEntries(): HasMany
    {
        return $this->hasMany(LedgerEntry::class);
    }

    public function balance(): float
    {
        return (float) $this->ledgerEntries()->sum('amount');
    }
}
