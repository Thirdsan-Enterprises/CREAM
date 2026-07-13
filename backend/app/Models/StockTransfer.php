<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

#[Fillable(['from_store_id', 'to_store_id', 'status', 'dispatched_by', 'dispatched_at', 'confirmed_by', 'confirmed_at'])]
class StockTransfer extends Model
{
    public const STATUS_DISPATCHED = 'dispatched';

    public const STATUS_CONFIRMED = 'confirmed';

    public const STATUS_DISCREPANCY = 'discrepancy';

    protected function casts(): array
    {
        return [
            'dispatched_at' => 'datetime',
            'confirmed_at' => 'datetime',
        ];
    }

    public function fromStore(): BelongsTo
    {
        return $this->belongsTo(Store::class, 'from_store_id');
    }

    public function toStore(): BelongsTo
    {
        return $this->belongsTo(Store::class, 'to_store_id');
    }

    public function dispatchedBy(): BelongsTo
    {
        return $this->belongsTo(User::class, 'dispatched_by');
    }

    public function confirmedBy(): BelongsTo
    {
        return $this->belongsTo(User::class, 'confirmed_by');
    }

    public function items(): HasMany
    {
        return $this->hasMany(StockTransferItem::class);
    }
}
