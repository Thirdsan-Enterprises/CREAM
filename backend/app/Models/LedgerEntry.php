<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

#[Fillable(['customer_id', 'type', 'amount', 'related_sale_id', 'note', 'recorded_by', 'occurred_at'])]
class LedgerEntry extends Model
{
    public const TYPE_DEPOSIT = 'deposit';

    public const TYPE_SALE_DEBIT = 'sale_debit';

    public const TYPE_ADJUSTMENT = 'adjustment';

    protected function casts(): array
    {
        return [
            'amount' => 'decimal:2',
            'occurred_at' => 'datetime',
        ];
    }

    public function customer(): BelongsTo
    {
        return $this->belongsTo(Customer::class);
    }

    public function recordedBy(): BelongsTo
    {
        return $this->belongsTo(User::class, 'recorded_by');
    }

    public function relatedSale(): BelongsTo
    {
        return $this->belongsTo(Sale::class, 'related_sale_id');
    }
}
