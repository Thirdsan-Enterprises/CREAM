<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

#[Fillable(['item_id', 'store_id', 'type', 'qty', 'related_transfer_id', 'note', 'user_id', 'occurred_at'])]
class StockMovement extends Model
{
    public const TYPE_PURCHASE = 'purchase';

    public const TYPE_TRANSFER_OUT = 'transfer_out';

    public const TYPE_TRANSFER_IN = 'transfer_in';

    public const TYPE_CONSUMPTION = 'consumption';

    public const TYPE_ADJUSTMENT = 'adjustment';

    protected function casts(): array
    {
        return [
            'qty' => 'decimal:2',
            'occurred_at' => 'datetime',
        ];
    }

    public function item(): BelongsTo
    {
        return $this->belongsTo(Item::class);
    }

    public function store(): BelongsTo
    {
        return $this->belongsTo(Store::class);
    }

    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }

    public function relatedTransfer(): BelongsTo
    {
        return $this->belongsTo(StockTransfer::class, 'related_transfer_id');
    }
}
