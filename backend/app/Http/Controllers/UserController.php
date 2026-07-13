<?php

namespace App\Http\Controllers;

use App\Models\User;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;
use Illuminate\Validation\Rules\Password;

class UserController extends Controller
{
    public function index()
    {
        return User::query()->with('store')->orderBy('name')->paginate();
    }

    public function store(Request $request)
    {
        $data = $request->validate([
            'name' => ['required', 'string', 'max:255'],
            'phone' => ['required', 'string', 'unique:users,phone'],
            'email' => ['nullable', 'email', 'unique:users,email'],
            'password' => ['required', Password::min(8)],
            'role' => ['required', Rule::in([
                User::ROLE_ADMIN, User::ROLE_STORE_MANAGER, User::ROLE_CASHIER, User::ROLE_STOREKEEPER,
            ])],
            'store_id' => ['nullable', 'exists:stores,id', 'required_unless:role,'.User::ROLE_ADMIN],
            'is_active' => ['boolean'],
        ]);

        $data['password'] = bcrypt($data['password']);

        return response()->json(User::create($data)->load('store'), 201);
    }

    public function update(Request $request, User $user)
    {
        $data = $request->validate([
            'name' => ['sometimes', 'string', 'max:255'],
            'phone' => ['sometimes', 'string', 'unique:users,phone,'.$user->id],
            'email' => ['nullable', 'email', 'unique:users,email,'.$user->id],
            'password' => ['sometimes', Password::min(8)],
            'role' => ['sometimes', Rule::in([
                User::ROLE_ADMIN, User::ROLE_STORE_MANAGER, User::ROLE_CASHIER, User::ROLE_STOREKEEPER,
            ])],
            'store_id' => ['nullable', 'exists:stores,id'],
            'is_active' => ['sometimes', 'boolean'],
        ]);

        if (isset($data['password'])) {
            $data['password'] = bcrypt($data['password']);
        }

        $user->update($data);

        return $user->load('store');
    }
}
