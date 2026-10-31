<?php

namespace App\Http\Controllers;

use App\Models\EditLog;
use App\Support\StoreScope;
use Carbon\CarbonImmutable;
use Illuminate\Http\Request;

/**
 * The record of changes: what was edited, by whom, and why. The owner sees
 * every branch; a store manager sees their own branch.
 */
class EditLogController extends Controller
{
    public function index(Request $request)
    {
        $user = $request->user();
        $storeId = StoreScope::resolve($user, $request->integer('store_id') ?: null);

        $query = EditLog::query()
            ->with(['user:id,name,role', 'store:id,name'])
            ->latest('created_at')->latest('id');

        if ($storeId !== null) {
            $query->where('store_id', $storeId);
        }
        if ($type = $request->string('subject_type')->toString()) {
            $query->where('subject_type', $type);
        }
        if ($request->filled('subject_id')) {
            $query->where('subject_id', $request->integer('subject_id'));
        }
        $tz = config('app.business_timezone', 'Africa/Kampala');
        if ($request->filled('from')) {
            $query->where('created_at', '>=', CarbonImmutable::parse($request->input('from'), $tz)->startOfDay()->utc());
        }
        if ($request->filled('to')) {
            $query->where('created_at', '<=', CarbonImmutable::parse($request->input('to'), $tz)->endOfDay()->utc());
        }

        return $query->paginate($this->perPage($request));
    }
}
