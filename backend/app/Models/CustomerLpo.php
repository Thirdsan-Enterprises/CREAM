<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

/** One LPO a company gave Cream: its value, plates and what it covers. */
#[Fillable(['customer_id', 'number', 'amount', 'plates', 'covers', 'note', 'created_by'])]
class CustomerLpo extends Model
{
    /** What an LPO can cover, as menu headings. */
    public const COVERS = ['Lunch', 'Breakfast', 'Drinks'];

    protected function casts(): array
    {
        return [
            'amount' => 'decimal:2',
            'plates' => 'integer',
            'covers' => 'array',
        ];
    }

    public function customer(): BelongsTo
    {
        return $this->belongsTo(Customer::class);
    }

    public function sales(): HasMany
    {
        return $this->hasMany(Sale::class);
    }

    /** Lunch plates charged to this LPO, voided sales left out. */
    public function platesUsed(): int
    {
        return (int) SaleItem::query()
            ->whereIn('sale_id', $this->sales()->whereNull('voided_at')->select('id'))
            ->where('item_type', SaleItem::TYPE_PLATE)
            ->sum('qty');
    }

    /** Money charged to this LPO, voided sales left out. */
    public function amountUsed(): float
    {
        return (float) $this->sales()->whereNull('voided_at')->sum('total');
    }

    public function covers(string $heading): bool
    {
        return in_array(strtolower($heading), array_map('strtolower', $this->covers ?? []), true);
    }

    public function summary(): array
    {
        $platesUsed = $this->platesUsed();

        return [
            'id' => $this->id,
            'number' => $this->number,
            'amount' => (float) $this->amount,
            'amount_used' => $this->amountUsed(),
            'plates' => $this->plates,
            'plates_used' => $platesUsed,
            'plates_left' => $this->plates === null ? null : max(0, $this->plates - $platesUsed),
            'covers' => $this->covers ?? [],
            'note' => $this->note,
            'created_at' => $this->created_at,
        ];
    }
}
