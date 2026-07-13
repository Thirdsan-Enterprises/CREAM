<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

#[Fillable([
    'client_name', 'client_phone', 'event_name', 'event_date', 'catering_package_id',
    'number_of_plates', 'total_amount', 'status', 'created_by',
])]
class CateringOrder extends Model
{
    use HasFactory;

    public const STATUS_QUOTED = 'quoted';

    public const STATUS_CONFIRMED = 'confirmed';

    public const STATUS_DELIVERED = 'delivered';

    public const STATUS_SETTLED = 'settled';

    public const STATUS_CANCELLED = 'cancelled';

    protected function casts(): array
    {
        return [
            'event_date' => 'date',
            'total_amount' => 'decimal:2',
        ];
    }

    public function package(): BelongsTo
    {
        return $this->belongsTo(CateringPackage::class, 'catering_package_id');
    }

    public function createdBy(): BelongsTo
    {
        return $this->belongsTo(User::class, 'created_by');
    }

    public function payments(): HasMany
    {
        return $this->hasMany(CateringPayment::class);
    }

    public function balanceDue(): float
    {
        return (float) $this->total_amount - (float) $this->payments()->sum('amount');
    }
}
