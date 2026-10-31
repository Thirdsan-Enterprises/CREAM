<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * One change to something already entered, with the reason for it. Written
 * through EditLog::record() so every change carries the same details.
 */
#[Fillable(['user_id', 'store_id', 'subject_type', 'subject_id', 'subject_label', 'action', 'changes', 'reason'])]
class EditLog extends Model
{
    public const UPDATED_AT = null;

    protected function casts(): array
    {
        return [
            'changes' => 'array',
            'created_at' => 'datetime',
        ];
    }

    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }

    public function store(): BelongsTo
    {
        return $this->belongsTo(Store::class);
    }

    /**
     * @param  array<string, array{from: mixed, to: mixed}>  $changes
     */
    public static function record(
        User $user,
        string $subjectType,
        ?int $subjectId,
        string $subjectLabel,
        string $action,
        array $changes,
        string $reason,
        ?int $storeId = null,
    ): self {
        return self::create([
            'user_id' => $user->id,
            'store_id' => $storeId,
            'subject_type' => $subjectType,
            'subject_id' => $subjectId,
            'subject_label' => $subjectLabel,
            'action' => $action,
            'changes' => $changes ?: null,
            'reason' => trim($reason),
        ]);
    }

    /**
     * {field: {from, to}} for the fields whose value actually changes.
     *
     * @param  array<string, mixed>  $before
     * @param  array<string, mixed>  $after
     * @return array<string, array{from: mixed, to: mixed}>
     */
    public static function diff(array $before, array $after): array
    {
        $changes = [];
        foreach ($after as $field => $to) {
            $from = $before[$field] ?? null;
            if (is_numeric($from) && is_numeric($to) ? (float) $from !== (float) $to : $from !== $to) {
                $changes[$field] = ['from' => $from, 'to' => $to];
            }
        }

        return $changes;
    }
}
