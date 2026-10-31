<?php

namespace Tests\Feature;

use App\Models\CateringOrder;
use App\Models\CateringPackage;
use App\Models\CateringPayment;
use App\Models\Customer;
use App\Models\DrinkPrice;
use App\Models\Item;
use App\Models\ItemStoreSetting;
use App\Models\LedgerEntry;
use App\Models\PlatePrice;
use App\Models\Sale;
use App\Models\SaleItem;
use App\Models\StockMovement;
use App\Models\StockTransfer;
use App\Models\StockTransferItem;
use App\Models\Store;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Tests\TestCase;

class ResetTrialDataTest extends TestCase
{
    use RefreshDatabase;

    private User $owner;

    private User $staff;

    private Store $kira;

    private Customer $customer;

    /** A system that has been played with: a bit of everything. */
    protected function setUp(): void
    {
        parent::setUp();

        $this->owner = User::factory()->create(['role' => User::ROLE_ADMIN, 'store_id' => null]);
        $this->kira = Store::factory()->create(['is_main' => true]);
        $lugogo = Store::factory()->create();
        $this->staff = User::factory()->create(['role' => User::ROLE_CASHIER, 'store_id' => $lugogo->id]);
        $this->owner->createToken('mobile');
        $this->staff->createToken('mobile');

        $item = Item::factory()->create();
        ItemStoreSetting::create(['item_id' => $item->id, 'store_id' => $this->kira->id, 'safety_stock' => 10]);
        PlatePrice::create(['store_id' => null, 'price' => 25000, 'effective_from' => now()->toDateString(), 'is_active' => true]);
        DrinkPrice::create(['item_id' => $item->id, 'store_id' => null, 'price' => 2000, 'effective_from' => now()->toDateString(), 'is_active' => true]);
        $package = CateringPackage::factory()->create();

        $this->customer = Customer::factory()->create(['created_by' => $this->staff->id]);
        $sale = Sale::create([
            'store_id' => $lugogo->id, 'sold_by' => $this->staff->id, 'payment_method' => 'account',
            'customer_id' => $this->customer->id, 'total' => 25000, 'sold_at' => now(),
        ]);
        SaleItem::create(['sale_id' => $sale->id, 'item_type' => 'plate', 'qty' => 1, 'unit_price' => 25000, 'line_total' => 25000]);
        LedgerEntry::create([
            'customer_id' => $this->customer->id, 'type' => 'sale_debit', 'amount' => -25000,
            'related_sale_id' => $sale->id, 'recorded_by' => $this->staff->id, 'occurred_at' => now(),
        ]);

        $transfer = StockTransfer::create([
            'from_store_id' => $this->kira->id, 'to_store_id' => $lugogo->id, 'status' => 'dispatched',
            'dispatched_by' => $this->owner->id, 'dispatched_at' => now(),
        ]);
        StockTransferItem::create(['stock_transfer_id' => $transfer->id, 'item_id' => $item->id, 'qty_dispatched' => 5]);
        StockMovement::create([
            'item_id' => $item->id, 'store_id' => $this->kira->id, 'type' => 'transfer_out', 'qty' => -5,
            'related_transfer_id' => $transfer->id, 'user_id' => $this->owner->id, 'occurred_at' => now(),
        ]);

        $order = CateringOrder::factory()->create(['catering_package_id' => $package->id, 'created_by' => $this->staff->id]);
        CateringPayment::create([
            'catering_order_id' => $order->id, 'amount' => 1000, 'payment_method' => 'cash',
            'paid_at' => now(), 'recorded_by' => $this->staff->id,
        ]);
    }

    private function tradingRecords(): int
    {
        return Sale::count() + SaleItem::count() + LedgerEntry::count() + StockMovement::count()
            + StockTransfer::count() + StockTransferItem::count() + CateringOrder::count() + CateringPayment::count();
    }

    public function test_without_force_it_only_reports_and_deletes_nothing(): void
    {
        $before = $this->tradingRecords();
        $this->assertGreaterThan(0, $before);

        $this->artisan('cream:reset-trial-data')
            ->expectsOutputToContain('Nothing was deleted')
            ->assertSuccessful();

        $this->assertSame($before, $this->tradingRecords());
    }

    public function test_force_clears_the_trial_records_and_keeps_the_setup(): void
    {
        $this->artisan('cream:reset-trial-data', ['--force' => true])
            ->expectsConfirmation('This permanently deletes the records above and sets every stock balance to 0. Continue?', 'yes')
            ->assertSuccessful();

        $this->assertSame(0, $this->tradingRecords());

        // The setup survives.
        $this->assertSame(2, Store::count());
        $this->assertSame(1, Item::count());
        $this->assertSame(1, ItemStoreSetting::count());
        $this->assertSame(1, PlatePrice::count());
        $this->assertSame(1, DrinkPrice::count());
        $this->assertSame(1, CateringPackage::count());
        $this->assertSame(2, User::count(), 'Staff are kept unless --users is given');
        $this->assertSame(1, Customer::count(), 'Customers are kept unless --customers is given');
        $this->assertSame(2, DB::table('personal_access_tokens')->count(), 'Nobody is signed out');
    }

    public function test_it_does_nothing_if_the_answer_is_no(): void
    {
        $before = $this->tradingRecords();

        $this->artisan('cream:reset-trial-data', ['--force' => true])
            ->expectsConfirmation('This permanently deletes the records above and sets every stock balance to 0. Continue?', 'no')
            ->assertFailed();

        $this->assertSame($before, $this->tradingRecords());
    }

    public function test_customers_and_staff_go_only_when_asked_and_the_owner_always_stays(): void
    {
        $this->artisan('cream:reset-trial-data', ['--force' => true, '--customers' => true, '--users' => true, '--no-interaction' => true])
            ->assertSuccessful();

        $this->assertSame(0, Customer::count());
        $this->assertSame(1, User::count());
        $this->assertSame(User::ROLE_ADMIN, User::first()->role);
        $this->assertSame(1, DB::table('personal_access_tokens')->count(), 'Only the owner keeps a token');
    }

    public function test_deleting_staff_keeps_customers_by_handing_them_to_the_owner(): void
    {
        $this->artisan('cream:reset-trial-data', ['--force' => true, '--users' => true, '--no-interaction' => true])
            ->assertSuccessful();

        $this->assertSame(1, Customer::count());
        $this->assertSame($this->owner->id, $this->customer->fresh()->created_by);
    }

    public function test_after_a_reset_the_system_still_works(): void
    {
        $this->artisan('cream:reset-trial-data', ['--force' => true, '--no-interaction' => true])->assertSuccessful();

        StockMovement::create([
            'item_id' => Item::first()->id, 'store_id' => $this->kira->id, 'type' => 'purchase', 'qty' => 40,
            'user_id' => $this->owner->id, 'occurred_at' => now(),
        ]);
        $status = $this->actingAs($this->owner)->getJson("/api/stock/status?store_id={$this->kira->id}")->json('items.0');

        $this->assertEquals(40, $status['balance']);
    }
}
