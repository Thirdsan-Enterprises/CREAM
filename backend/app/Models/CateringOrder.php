<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

#[Fillable([
    'client_name', 'client_phone', 'event_name', 'event_date', 'catering_package_id',
    'price_per_plate', 'number_of_plates', 'notes', 'total_amount', 'status', 'created_by',
])]
class CateringOrder extends Model
{
    use HasFactory;

    public const STATUS_QUOTED = 'quoted';

    public const STATUS_CONFIRMED = 'confirmed';

    public const STATUS_DELIVERED = 'delivered';

    public const STATUS_SETTLED = 'settled';

    public const STATUS_CANCELLED = 'cancelled';

    /**
     * Non-refundable share of a cancelled order's deposits, per the client's
     * booking policy: cancelling forfeits half of whatever had been paid
     * toward securing the date.
     */
    public const CANCELLATION_FEE_RATE = 0.5;

    protected function casts(): array
    {
        return [
            'event_date' => 'date',
            'price_per_plate' => 'decimal:2',
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

    public function depositedTotal(): float
    {
        return (float) $this->payments()->sum('amount');
    }

    public function balanceDue(): float
    {
        return (float) $this->total_amount - $this->depositedTotal();
    }

    /**
     * Non-refundable amount if this order is cancelled: half of whatever
     * has been deposited so far, forfeited as a booking fee.
     */
    public function cancellationFee(): float
    {
        return round($this->depositedTotal() * self::CANCELLATION_FEE_RATE, 2);
    }

    public function refundableAmount(): float
    {
        return round($this->depositedTotal() - $this->cancellationFee(), 2);
    }

    /**
     * Extra numbers the client asked to see per status: how much has been
     * deposited, what's still owed, and — specifically for a cancelled
     * booking — the 50% non-refundable fee vs. what's still refundable.
     */
    public function financialSummary(): array
    {
        return [
            'total_amount' => (float) $this->total_amount,
            'deposited_total' => $this->depositedTotal(),
            'balance_due' => $this->balanceDue(),
            'cancellation_fee' => $this->cancellationFee(),
            'refundable_amount' => $this->refundableAmount(),
        ];
    }
}
