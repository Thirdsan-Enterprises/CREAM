<?php

namespace App\Support;

use App\Models\User;
use Illuminate\Validation\ValidationException;

/**
 * Server-side store scoping: a non-admin's own store_id always wins,
 * regardless of any store_id the client attempts to pass.
 */
class StoreScope
{
    public static function resolve(User $user, ?int $requestedStoreId): ?int
    {
        if ($user->isAdmin()) {
            return $requestedStoreId;
        }

        return $user->store_id;
    }

    public static function resolveRequired(User $user, ?int $requestedStoreId): int
    {
        $storeId = self::resolve($user, $requestedStoreId);

        if ($storeId === null) {
            throw ValidationException::withMessages([
                'store_id' => ['A store_id is required.'],
            ]);
        }

        return $storeId;
    }

    public static function assertAccess(User $user, int $storeId): void
    {
        if (! $user->isAdmin() && $user->store_id !== $storeId) {
            abort(403, 'You do not have access to this store.');
        }
    }
}
