<?php

namespace App\Console\Commands;

use App\Models\User;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\DB;

/**
 * Clears the records made while trying the system out, ready for go-live.
 *
 * Deleted: sales, stock movements (every balance returns to 0, including
 * today's plates and purchase prices), transfers, branch stock requests,
 * expenses, catering orders and their payments, account ledger entries and
 * the Changes log. Optionally the customer accounts (--customers) and the
 * staff accounts (--users).
 *
 * Kept: branches, the menu and kitchen stock items, re-order levels, plate,
 * menu and packing prices, catering packages, and the owner (admin)
 * account. Nothing here is
 * recoverable, so it only reports what it would delete unless --force is
 * given, and it asks before deleting.
 */
class ResetTrialData extends Command
{
    protected $signature = 'cream:reset-trial-data
        {--customers : Also delete every customer account}
        {--users : Also delete every staff account except the owner (admins)}
        {--force : Really delete. Without it this only shows what would go}';

    protected $description = 'Delete trial sales, stock movements, transfers, catering and ledger records (setup is kept)';

    public function handle(): int
    {
        $plan = $this->plan();

        $this->components->info('Records that '.($this->option('force') ? 'will be' : 'would be').' deleted');
        $this->table(
            ['What', 'Records'],
            array_map(fn ($label, $count) => [$label, $count], array_keys($plan), array_values($plan)),
        );
        $this->line('Kept: branches, menu and kitchen stock items, re-order levels, prices, catering packages and the owner account.');

        if (! $this->option('force')) {
            $this->newLine();
            $this->components->warn('Nothing was deleted. Take a database backup, then run again with --force.');

            return self::SUCCESS;
        }

        if ($this->input->isInteractive()
            && ! $this->confirm('This permanently deletes the records above and sets every stock balance to 0. Continue?', false)) {
            $this->components->warn('Cancelled. Nothing was deleted.');

            return self::FAILURE;
        }

        DB::transaction(function () {
            // Children before parents, so no foreign key is ever broken.
            DB::table('sale_items')->delete();
            DB::table('ledger_entries')->delete();
            DB::table('sales')->delete();
            // LPOs brought during the trial; their value was in the ledger.
            DB::table('customer_lpos')->delete();

            DB::table('expenses')->delete();

            // A request points at the transfer that answered it.
            DB::table('stock_request_items')->delete();
            DB::table('stock_requests')->delete();

            DB::table('stock_movements')->delete();
            DB::table('stock_transfer_items')->delete();
            DB::table('stock_transfers')->delete();

            DB::table('catering_payments')->delete();
            DB::table('catering_orders')->delete();

            // The trial's voids, corrections and price changes.
            DB::table('edit_logs')->delete();

            if ($this->option('customers')) {
                DB::table('customers')->delete();
            }

            if ($this->option('users')) {
                $this->deleteStaff();
            }
        });

        $this->components->info('Trial data deleted. Record the real opening stock before you start trading.');

        return self::SUCCESS;
    }

    /** @return array<string, int> */
    private function plan(): array
    {
        $plan = [
            'Sales (and their lines)' => DB::table('sales')->count(),
            'Account ledger entries' => DB::table('ledger_entries')->count(),
            'LPOs recorded' => DB::table('customer_lpos')->count(),
            'Stock movements (balances reset to 0)' => DB::table('stock_movements')->count(),
            'Stock transfers' => DB::table('stock_transfers')->count(),
            'Branch stock requests' => DB::table('stock_requests')->count(),
            'Expenses' => DB::table('expenses')->count(),
            'Changes log entries' => DB::table('edit_logs')->count(),
            'Catering orders' => DB::table('catering_orders')->count(),
            'Catering payments' => DB::table('catering_payments')->count(),
        ];

        if ($this->option('customers')) {
            $plan['Customer accounts'] = DB::table('customers')->count();
        }
        if ($this->option('users')) {
            $plan['Staff accounts (all but owners)'] = DB::table('users')->where('role', '!=', User::ROLE_ADMIN)->count();
        }

        return $plan;
    }

    private function deleteStaff(): void
    {
        $staff = DB::table('users')->where('role', '!=', User::ROLE_ADMIN)->pluck('id');
        $owner = DB::table('users')->where('role', User::ROLE_ADMIN)->orderBy('id')->value('id');

        // Customer accounts that are kept were created by some staff member;
        // hand them to the owner so no record points at a deleted person.
        if ($owner !== null) {
            DB::table('customers')->whereIn('created_by', $staff)->update(['created_by' => $owner]);
        }

        DB::table('personal_access_tokens')
            ->where('tokenable_type', User::class)
            ->whereIn('tokenable_id', $staff)
            ->delete();

        DB::table('users')->whereIn('id', $staff)->delete();
    }
}
