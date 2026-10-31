<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

#[Fillable(['stock_request_id', 'item_id', 'qty_requested', 'qty_sent'])]
class StockRequestItem extends Model
{
    protected function casts(): array
    {
        return [
            'qty_requested' => 'decimal:2',
            'qty_sent' => 'decimal:2',
        ];
    }

    public function item(): BelongsTo
    {
        return $this->belongsTo(Item::class);
    }
}
