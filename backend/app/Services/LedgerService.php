<?php

namespace App\Services;

use App\Models\Customer;
use App\Models\LedgerEntry;
use Illuminate\Validation\ValidationException;

class LedgerService
{
    public function debit(Customer $customer, float $amount, ?int $relatedSaleId, int $recordedBy, ?string $note = null): LedgerEntry
    {
        $projected = $customer->balance() - $amount;
        $floor = $customer->account_type === Customer::TYPE_CREDIT ? -1 * (float) $customer->credit_limit : 0.0;

        if ($projected < $floor) {
            throw ValidationException::withMessages([
                'customer_id' => [$customer->account_type === Customer::TYPE_CREDIT
                    ? 'This charge would exceed the customer\'s credit limit.'
                    : 'This customer does not have sufficient prepaid balance.'],
            ]);
        }

        return LedgerEntry::create([
            'customer_id' => $customer->id,
            'type' => LedgerEntry::TYPE_SALE_DEBIT,
            'amount' => -$amount,
            'related_sale_id' => $relatedSaleId,
            'note' => $note,
            'recorded_by' => $recordedBy,
            'occurred_at' => now(),
        ]);
    }

    public function deposit(Customer $customer, float $amount, int $recordedBy, ?string $note = null): LedgerEntry
    {
        return LedgerEntry::create([
            'customer_id' => $customer->id,
            'type' => LedgerEntry::TYPE_DEPOSIT,
            'amount' => $amount,
            'note' => $note,
            'recorded_by' => $recordedBy,
            'occurred_at' => now(),
        ]);
    }
}
