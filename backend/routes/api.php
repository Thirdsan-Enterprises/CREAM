<?php

use App\Http\Controllers\Auth\AuthController;
use App\Http\Controllers\ItemController;
use App\Http\Controllers\StockMovementController;
use App\Http\Controllers\StockTransferController;
use App\Http\Controllers\StoreController;
use App\Http\Controllers\UserController;
use App\Models\User;
use Illuminate\Support\Facades\Route;

Route::post('/auth/login', [AuthController::class, 'login']);

Route::middleware('auth:sanctum')->group(function () {
    Route::post('/auth/logout', [AuthController::class, 'logout']);
    Route::get('/auth/me', [AuthController::class, 'me']);

    Route::get('/stores', [StoreController::class, 'index']);
    Route::get('/items', [ItemController::class, 'index']);
    Route::get('/items/{item}/balances', [ItemController::class, 'balances']);

    Route::get('/stock/movements', [StockMovementController::class, 'index']);
    Route::get('/transfers', [StockTransferController::class, 'index']);
    Route::get('/transfers/{transfer}', [StockTransferController::class, 'show']);

    Route::middleware('role:'.User::ROLE_ADMIN)->group(function () {
        Route::post('/stores', [StoreController::class, 'store']);
        Route::patch('/stores/{store}', [StoreController::class, 'update']);

        Route::get('/users', [UserController::class, 'index']);
        Route::post('/users', [UserController::class, 'store']);
        Route::patch('/users/{user}', [UserController::class, 'update']);

        Route::post('/items', [ItemController::class, 'store']);
        Route::patch('/items/{item}', [ItemController::class, 'update']);
        Route::post('/items/{item}/store-settings', [ItemController::class, 'setStoreSettings']);
    });

    Route::middleware('role:'.User::ROLE_ADMIN.','.User::ROLE_STOREKEEPER.','.User::ROLE_STORE_MANAGER)->group(function () {
        Route::post('/stock/purchase', [StockMovementController::class, 'purchase']);
        Route::post('/transfers', [StockTransferController::class, 'store']);
        Route::post('/transfers/{transfer}/confirm', [StockTransferController::class, 'confirm']);
    });

    Route::middleware('role:'.User::ROLE_ADMIN.','.User::ROLE_STORE_MANAGER.','.User::ROLE_CASHIER.','.User::ROLE_STOREKEEPER)->group(function () {
        Route::post('/stock/consumption', [StockMovementController::class, 'consumption']);
    });

    Route::middleware('role:'.User::ROLE_ADMIN.','.User::ROLE_STORE_MANAGER)->group(function () {
        Route::post('/stock/adjustment', [StockMovementController::class, 'adjustment']);
    });
});
