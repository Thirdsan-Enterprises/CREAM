<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

/** A branch asking the procurement unit for items it is missing. */
#[Fillable(['store_id', 'requested_by', 'status', 'note', 'responded_by', 'responded_at', 'response_note', 'stock_transfer_id'])]
class StockRequest extends Model
{
    public const STATUS_OPEN = 'open';

    public const STATUS_SENT = 'sent';

    public const STATUS_DECLINED = 'declined';

    public const STATUS_CANCELLED = 'cancelled';

    protected function casts(): array
    {
        return ['responded_at' => 'datetime'];
    }

    public function store(): BelongsTo
    {
        return $this->belongsTo(Store::class);
    }

    public function requestedBy(): BelongsTo
    {
        return $this->belongsTo(User::class, 'requested_by');
    }

    public function respondedBy(): BelongsTo
    {
        return $this->belongsTo(User::class, 'responded_by');
    }

    public function transfer(): BelongsTo
    {
        return $this->belongsTo(StockTransfer::class, 'stock_transfer_id');
    }

    public function items(): HasMany
    {
        return $this->hasMany(StockRequestItem::class);
    }
}
