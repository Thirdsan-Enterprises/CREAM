<?php

namespace App\Services;

use App\Models\Customer;

/**
 * How much a customer can still spend and whether staff should be warned:
 *
 *  - ok:      plenty left.
 *  - low:     a credit customer has used 80% or more of their limit, or
 *             what is left would not cover a plate at their branch.
 *  - blocked: nothing left to spend: take a deposit or payment first.
 */
class CustomerStanding
{
    public const WARN_AT_PCT = 80;

    public function __construct(private readonly PricingService $pricingService) {}

    /**
     * @return array{balance: float, available: float, credit_used_pct: ?float, status: string, warning: ?string}
     */
    public function for(Customer $customer, ?float $balance = null): array
    {
        $balance ??= $customer->balance();
        $limit = (float) $customer->credit_limit;
        $isCredit = $customer->account_type === Customer::TYPE_CREDIT;
        $available = $isCredit ? $balance + $limit : $balance;
        $plate = $this->pricingService->currentPlatePrice($customer->store_id);

        $usedPct = null;
        if ($isCredit && $limit > 0) {
            $usedPct = round(max(0, -$balance) / $limit * 100, 1);
        }

        $status = 'ok';
        if ($available <= 0) {
            $status = 'blocked';
        } elseif (($usedPct !== null && $usedPct >= self::WARN_AT_PCT) || $available < $plate) {
            $status = 'low';
        }

        return [
            'balance' => $balance,
            'available' => max(0, $available),
            'credit_used_pct' => $usedPct,
            'status' => $status,
            'warning' => $this->warning($customer, $status, $available, $usedPct, $limit),
        ];
    }

    private function warning(Customer $customer, string $status, float $available, ?float $usedPct, float $limit): ?string
    {
        if ($status === 'ok') {
            return null;
        }
        $left = 'UGX '.number_format(max(0, $available));

        if ($customer->account_type === Customer::TYPE_CREDIT) {
            return $status === 'blocked'
                ? "{$customer->name} has reached the credit limit. Collect a payment before charging more."
                : "{$customer->name} has used ".round($usedPct ?? 100).'% of the credit limit (UGX '.number_format($limit)."): {$left} left.";
        }

        return $status === 'blocked'
            ? "{$customer->name}'s balance is used up. Take a deposit before charging more."
            : "{$customer->name} has only {$left} left, less than a plate.";
    }
}
