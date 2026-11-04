<?php

use App\Http\Controllers\Auth\AuthController;
use App\Http\Controllers\BranchReportController;
use App\Http\Controllers\CateringOrderController;
use App\Http\Controllers\CateringPackageController;
use App\Http\Controllers\CustomerController;
use App\Http\Controllers\DailyPlatesController;
use App\Http\Controllers\DayReportController;
use App\Http\Controllers\DrinkController;
use App\Http\Controllers\EditLogController;
use App\Http\Controllers\ExpenseController;
use App\Http\Controllers\ItemController;
use App\Http\Controllers\MenuController;
use App\Http\Controllers\PlatePriceController;
use App\Http\Controllers\PriceListController;
use App\Http\Controllers\PurchaseLedgerController;
use App\Http\Controllers\ReceiptController;
use App\Http\Controllers\ReportController;
use App\Http\Controllers\SaleController;
use App\Http\Controllers\StockMovementController;
use App\Http\Controllers\StockRequestController;
use App\Http\Controllers\StockTransferController;
use App\Http\Controllers\StoreController;
use App\Http\Controllers\UserController;
use App\Models\User;
use Illuminate\Support\Facades\Route;

Route::post('/auth/login', [AuthController::class, 'login']);

Route::middleware('auth:sanctum')->group(function () {
    // Today's plates: every role (procurement sets lunch for each branch).
    Route::get('/daily-plates', [DailyPlatesController::class, 'index']);
    Route::post('/daily-plates', [DailyPlatesController::class, 'store']);
    Route::post('/auth/logout', [AuthController::class, 'logout']);
    Route::get('/auth/me', [AuthController::class, 'me']);

    Route::get('/stores', [StoreController::class, 'index']);

    Route::get('/plate-price', [PlatePriceController::class, 'show']);
    Route::get('/drinks', [DrinkController::class, 'index']);
    Route::get('/menu', [MenuController::class, 'index']);

    // Kitchen stock (raw materials) is for the owner, procurement and store
    // managers. Cashiers only see the menu.
    Route::middleware('role:'.User::ROLE_ADMIN.','.User::ROLE_STORE_MANAGER.','.User::ROLE_STOREKEEPER)->group(function () {
        Route::get('/items', [ItemController::class, 'index']);
        Route::get('/items/{item}/balances', [ItemController::class, 'balances']);
        // Owner and procurement only (checked in the controller).
        Route::post('/items', [ItemController::class, 'store']);
        Route::patch('/items/{item}', [ItemController::class, 'update']);
        Route::delete('/items/{item}', [ItemController::class, 'destroy']);
        Route::post('/items/{item}/store-settings', [ItemController::class, 'setStoreSettings']);

        Route::get('/stock/movements', [StockMovementController::class, 'index']);
        Route::get('/stock/status', [StockMovementController::class, 'status']);
        Route::get('/transfers', [StockTransferController::class, 'index']);
        Route::get('/transfers/{transfer}', [StockTransferController::class, 'show']);

        Route::get('/stock-requests', [StockRequestController::class, 'index']);
        Route::post('/stock-requests', [StockRequestController::class, 'store']);
        Route::get('/stock-requests/{stockRequest}', [StockRequestController::class, 'show']);
        Route::post('/stock-requests/{stockRequest}/send', [StockRequestController::class, 'send']);
        Route::post('/stock-requests/{stockRequest}/decline', [StockRequestController::class, 'decline']);
        Route::post('/stock-requests/{stockRequest}/cancel', [StockRequestController::class, 'cancel']);
    });

    Route::get('/sales', [SaleController::class, 'index']);
    Route::get('/sales/summary', [SaleController::class, 'summary']);
    Route::get('/sales/{sale}/receipt', [ReceiptController::class, 'show']);

    Route::middleware('role:'.User::ROLE_ADMIN.','.User::ROLE_STORE_MANAGER)->group(function () {
        Route::get('/edit-logs', [EditLogController::class, 'index']);
        Route::patch('/customers/{customer}', [CustomerController::class, 'update']);
        Route::post('/customers/{customer}/adjustment', [CustomerController::class, 'adjust']);
    });

    Route::middleware('role:'.User::ROLE_ADMIN.','.User::ROLE_STORE_MANAGER.','.User::ROLE_CASHIER)->group(function () {
        Route::post('/sales', [SaleController::class, 'store']);
        Route::get('/expenses', [ExpenseController::class, 'index']);
        Route::post('/expenses', [ExpenseController::class, 'store']);
        Route::post('/expenses/{expense}/void', [ExpenseController::class, 'void']);
        Route::get('/reports/my-day', [DayReportController::class, 'show']);
        // Cashiers: only their own sale, within minutes (checked in the controller).
        Route::post('/sales/{sale}/void', [SaleController::class, 'void']);

        Route::get('/customers', [CustomerController::class, 'index']);
        Route::post('/customers', [CustomerController::class, 'store']);
        Route::get('/customers/{customer}', [CustomerController::class, 'show']);
        Route::get('/customers/{customer}/statement', [CustomerController::class, 'statement']);
        Route::get('/customers/{customer}/balance', [CustomerController::class, 'balance']);
        Route::post('/customers/{customer}/deposit', [CustomerController::class, 'deposit']);
        Route::get('/customers/{customer}/lpos', [CustomerController::class, 'lpos']);
        Route::post('/customers/{customer}/lpos', [CustomerController::class, 'addLpo']);
    });

    Route::middleware('role:'.User::ROLE_ADMIN)->group(function () {
        Route::patch('/customers/{customer}/lpos/{lpo}', [CustomerController::class, 'updateLpo']);
        Route::post('/stores', [StoreController::class, 'store']);
        Route::patch('/stores/{store}', [StoreController::class, 'update']);

        Route::get('/users', [UserController::class, 'index']);
        Route::post('/users', [UserController::class, 'store']);
        Route::patch('/users/{user}', [UserController::class, 'update']);

        Route::patch('/plate-price', [PlatePriceController::class, 'update']);
        Route::post('/drinks', [DrinkController::class, 'store']);
        Route::patch('/drinks/{item}', [DrinkController::class, 'update']);
        Route::post('/menu-items', [MenuController::class, 'store']);
        Route::patch('/menu-items/{item}', [MenuController::class, 'update']);
        Route::get('/price-list', [PriceListController::class, 'index']);

        Route::get('/catering-packages', [CateringPackageController::class, 'index']);
        Route::post('/catering-packages', [CateringPackageController::class, 'store']);
        Route::patch('/catering-packages/{cateringPackage}', [CateringPackageController::class, 'update']);

        Route::get('/catering-orders', [CateringOrderController::class, 'index']);
        Route::post('/catering-orders', [CateringOrderController::class, 'store']);
        Route::get('/catering-orders/{cateringOrder}', [CateringOrderController::class, 'show']);
        Route::patch('/catering-orders/{cateringOrder}', [CateringOrderController::class, 'update']);
        Route::post('/catering-orders/{cateringOrder}/payments', [CateringOrderController::class, 'addPayment']);

        Route::get('/reports/dashboard', [ReportController::class, 'dashboard']);
        Route::get('/reports/outstanding-credit', [ReportController::class, 'outstandingCredit']);
        Route::get('/reports/catering-pipeline', [ReportController::class, 'cateringPipeline']);
        Route::get('/reports/branches', [BranchReportController::class, 'index']);
    });

    Route::middleware('role:'.User::ROLE_ADMIN.','.User::ROLE_STOREKEEPER.','.User::ROLE_STORE_MANAGER)->group(function () {
        Route::post('/stock/purchase', [StockMovementController::class, 'purchase']);
        // Every branch's stock at a glance, for deciding what to send.
        Route::get('/reports/stock-status', [ReportController::class, 'stockStatus']);
        Route::get('/purchases', [PurchaseLedgerController::class, 'index']);
        Route::post('/transfers', [StockTransferController::class, 'store']);
        Route::post('/transfers/{transfer}/confirm', [StockTransferController::class, 'confirm']);
    });

    Route::middleware('role:'.User::ROLE_ADMIN.','.User::ROLE_STORE_MANAGER.','.User::ROLE_STOREKEEPER)->group(function () {
        Route::post('/stock/consumption', [StockMovementController::class, 'consumption']);
    });

    Route::middleware('role:'.User::ROLE_ADMIN.','.User::ROLE_STORE_MANAGER)->group(function () {
        Route::post('/stock/adjustment', [StockMovementController::class, 'adjustment']);
        Route::get('/reports/branches/{store}', [BranchReportController::class, 'show']);
    });
});
