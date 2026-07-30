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
            $message = match ($customer->account_type) {
                Customer::TYPE_CREDIT => 'This charge would exceed the customer\'s credit limit.',
                Customer::TYPE_LPO => 'This customer does not have sufficient LPO balance remaining.',
                default => 'This customer does not have sufficient prepaid balance.',
            };

            throw ValidationException::withMessages(['customer_id' => [$message]]);
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
