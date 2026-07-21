import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/api/repositories/items_repository.dart';
import '../../core/api/repositories/stores_repository.dart';
import '../../core/api/repositories/users_repository.dart';
import '../../core/auth/auth_session.dart';
import '../../core/auth/store.dart';
import '../../shared/formatters/currency_formatter.dart';
import '../../shared/models/item.dart';

const _roles = ['admin', 'store_manager', 'cashier', 'storekeeper'];

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Column(
        children: [
          Material(
            color: Theme.of(context).scaffoldBackgroundColor,
            child: const TabBar(
              tabs: [
                Tab(text: 'Stores'),
                Tab(text: 'Users'),
                Tab(text: 'Items'),
                Tab(text: 'Plate price'),
              ],
            ),
          ),
          const Expanded(
            child: TabBarView(
              children: [
                _StoresTab(),
                _UsersTab(),
                _ItemsTab(),
                _PlatePriceTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StoresTab extends ConsumerStatefulWidget {
  const _StoresTab();

  @override
  ConsumerState<_StoresTab> createState() => _StoresTabState();
}

class _StoresTabState extends ConsumerState<_StoresTab> {
  late Future<List<Store>> _future;

  @override
  void initState() {
    super.initState();
    _future = ref.read(storesRepositoryProvider).all();
  }

  void _reload() =>
      setState(() => _future = ref.read(storesRepositoryProvider).all());

  Future<void> _createStore() async {
    final nameController = TextEditingController();
    final codeController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New store'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            TextField(
              controller: codeController,
              decoration: const InputDecoration(labelText: 'Code'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Create'),
          ),
        ],
      ),
    );

    if (confirmed != true ||
        nameController.text.isEmpty ||
        codeController.text.isEmpty) {
      return;
    }

    try {
      await ref
          .read(storesRepositoryProvider)
          .create(name: nameController.text, code: codeController.text);
      _reload();
    } catch (e) {
      if (!mounted) return;
      final message = e is ApiException ? e.message : 'Something went wrong.';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FutureBuilder<List<Store>>(
        future: _future,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final stores = snapshot.data!;

          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: stores.length,
            itemBuilder: (context, index) {
              final store = stores[index];
              return Card(
                child: ListTile(
                  title: Text(store.name),
                  subtitle: Text(store.code),
                  trailing: store.isMain
                      ? const Chip(label: Text('Main'))
                      : null,
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _createStore,
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _UsersTab extends ConsumerStatefulWidget {
  const _UsersTab();

  @override
  ConsumerState<_UsersTab> createState() => _UsersTabState();
}

class _UsersTabState extends ConsumerState<_UsersTab> {
  late Future<List<ManagedUser>> _future;

  @override
  void initState() {
    super.initState();
    _future = ref.read(usersRepositoryProvider).all();
  }

  void _reload() =>
      setState(() => _future = ref.read(usersRepositoryProvider).all());

  Future<void> _createUser() async {
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) => const _NewUserSheet(),
    );
    if (created == true) _reload();
  }

  Future<void> _editUser(ManagedUser user) async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _EditUserSheet(user: user),
    );
    if (changed == true) _reload();
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = ref.watch(authSessionProvider).user?.id;

    return Scaffold(
      body: FutureBuilder<List<ManagedUser>>(
        future: _future,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final users = snapshot.data!;

          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: users.length,
            itemBuilder: (context, index) {
              final user = users[index];
              final isYou = user.id == currentUserId;
              return Card(
                child: ListTile(
                  title: Text(isYou ? '${user.name} (you)' : user.name),
                  subtitle: Text(
                    '${user.phone} — ${user.role}${user.store != null ? ' — ${user.store!.name}' : ''}',
                  ),
                  onTap: () => _editUser(user),
                  trailing: Switch(
                    value: user.isActive,
                    onChanged: (value) async {
                      await ref
                          .read(usersRepositoryProvider)
                          .update(user.id, isActive: value);
                      _reload();
                    },
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _createUser,
        child: const Icon(Icons.add),
      ),
    );
  }
}

/// Edit an existing user's details, role/store, or reset their password —
/// including an admin editing their own account. Leave the password field
/// blank to keep the current one.
class _EditUserSheet extends ConsumerStatefulWidget {
  const _EditUserSheet({required this.user});

  final ManagedUser user;

  @override
  ConsumerState<_EditUserSheet> createState() => _EditUserSheetState();
}

class _EditUserSheetState extends ConsumerState<_EditUserSheet> {
  late final _nameController = TextEditingController(text: widget.user.name);
  late final _phoneController = TextEditingController(text: widget.user.phone);
  final _passwordController = TextEditingController();
  late String _role = widget.user.role;
  late Store? _store = widget.user.store;
  bool _submitting = false;
  late Future<List<Store>> _storesFuture;

  @override
  void initState() {
    super.initState();
    _storesFuture = ref.read(storesRepositoryProvider).all();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_nameController.text.isEmpty || _phoneController.text.isEmpty) return;
    if (_role != 'admin' && _store == null) return;
    if (_passwordController.text.isNotEmpty &&
        _passwordController.text.length < 8) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password must be at least 8 characters.')),
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      await ref
          .read(usersRepositoryProvider)
          .update(
            widget.user.id,
            name: _nameController.text,
            phone: _phoneController.text,
            password: _passwordController.text,
            role: _role,
            storeId: _role == 'admin' ? null : _store?.id,
          );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      final message = e is ApiException ? e.message : 'Something went wrong.';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: FutureBuilder<List<Store>>(
        future: _storesFuture,
        builder: (context, snapshot) {
          final stores = snapshot.data ?? [];

          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Edit user', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _phoneController,
                decoration: const InputDecoration(labelText: 'Phone'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _passwordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'New password (leave blank to keep current)',
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _role,
                decoration: const InputDecoration(labelText: 'Role'),
                items: [
                  for (final role in _roles)
                    DropdownMenuItem(value: role, child: Text(role)),
                ],
                onChanged: (value) => setState(() => _role = value!),
              ),
              if (_role != 'admin') ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<Store>(
                  initialValue: stores
                      .where((s) => s.id == _store?.id)
                      .firstOrNull,
                  decoration: const InputDecoration(labelText: 'Store'),
                  items: [
                    for (final store in stores)
                      DropdownMenuItem(value: store, child: Text(store.name)),
                  ],
                  onChanged: (value) => setState(() => _store = value),
                ),
              ],
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _submitting ? null : _submit,
                child: _submitting
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Save changes'),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _NewUserSheet extends ConsumerStatefulWidget {
  const _NewUserSheet();

  @override
  ConsumerState<_NewUserSheet> createState() => _NewUserSheetState();
}

class _NewUserSheetState extends ConsumerState<_NewUserSheet> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  String _role = 'cashier';
  Store? _store;
  bool _submitting = false;
  late Future<List<Store>> _storesFuture;

  @override
  void initState() {
    super.initState();
    _storesFuture = ref.read(storesRepositoryProvider).all();
  }

  Future<void> _submit() async {
    if (_nameController.text.isEmpty ||
        _phoneController.text.isEmpty ||
        _passwordController.text.isEmpty) {
      return;
    }
    if (_role != 'admin' && _store == null) return;

    setState(() => _submitting = true);
    try {
      await ref
          .read(usersRepositoryProvider)
          .create(
            name: _nameController.text,
            phone: _phoneController.text,
            password: _passwordController.text,
            role: _role,
            storeId: _role == 'admin' ? null : _store?.id,
          );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      final message = e is ApiException ? e.message : 'Something went wrong.';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: FutureBuilder<List<Store>>(
        future: _storesFuture,
        builder: (context, snapshot) {
          final stores = snapshot.data ?? [];

          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('New user', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _phoneController,
                decoration: const InputDecoration(labelText: 'Phone'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _passwordController,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Password'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _role,
                decoration: const InputDecoration(labelText: 'Role'),
                items: [
                  for (final role in _roles)
                    DropdownMenuItem(value: role, child: Text(role)),
                ],
                onChanged: (value) => setState(() => _role = value!),
              ),
              if (_role != 'admin') ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<Store>(
                  initialValue: _store,
                  decoration: const InputDecoration(labelText: 'Store'),
                  items: [
                    for (final store in stores)
                      DropdownMenuItem(value: store, child: Text(store.name)),
                  ],
                  onChanged: (value) => setState(() => _store = value),
                ),
              ],
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _submitting ? null : _submit,
                child: _submitting
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Create user'),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ItemsTab extends ConsumerStatefulWidget {
  const _ItemsTab();

  @override
  ConsumerState<_ItemsTab> createState() => _ItemsTabState();
}

class _ItemsTabState extends ConsumerState<_ItemsTab> {
  late Future<List<Item>> _future;

  @override
  void initState() {
    super.initState();
    _future = ref.read(itemsRepositoryProvider).items();
  }

  void _reload() =>
      setState(() => _future = ref.read(itemsRepositoryProvider).items());

  Future<void> _createItem() async {
    final nameController = TextEditingController();
    final unitController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New item'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            TextField(
              controller: unitController,
              decoration: const InputDecoration(
                labelText: 'Unit (kg, piece, ...)',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Create'),
          ),
        ],
      ),
    );

    if (confirmed != true ||
        nameController.text.isEmpty ||
        unitController.text.isEmpty) {
      return;
    }
    await ref
        .read(itemsRepositoryProvider)
        .createItem(name: nameController.text, unit: unitController.text);
    _reload();
  }

  Future<void> _setSafetyStock(Item item) async {
    final stores = await ref.read(storesRepositoryProvider).all();
    if (!mounted) return;

    Store? selectedStore = stores.firstOrNull;
    final controller = TextEditingController(text: '0');

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Safety stock — ${item.name}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<Store>(
                initialValue: selectedStore,
                decoration: const InputDecoration(labelText: 'Store'),
                items: [
                  for (final store in stores)
                    DropdownMenuItem(value: store, child: Text(store.name)),
                ],
                onChanged: (value) =>
                    setDialogState(() => selectedStore = value),
              ),
              TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Safety stock'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    final safetyStock = double.tryParse(controller.text);
    if (confirmed != true || selectedStore == null || safetyStock == null) {
      return;
    }

    await ref
        .read(itemsRepositoryProvider)
        .setStoreSettings(
          itemId: item.id,
          storeId: selectedStore!.id,
          safetyStock: safetyStock,
        );
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Safety stock updated.')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FutureBuilder<List<Item>>(
        future: _future,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final items = snapshot.data!;

          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              return Card(
                child: ListTile(
                  title: Text(item.name),
                  subtitle: Text(item.unit),
                  trailing: TextButton(
                    onPressed: () => _setSafetyStock(item),
                    child: const Text('Safety stock'),
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _createItem,
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _PlatePriceTab extends ConsumerStatefulWidget {
  const _PlatePriceTab();

  @override
  ConsumerState<_PlatePriceTab> createState() => _PlatePriceTabState();
}

class _PlatePriceTabState extends ConsumerState<_PlatePriceTab> {
  late Future<double> _future;
  final _controller = TextEditingController();
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _future = ref.read(itemsRepositoryProvider).platePrice();
  }

  Future<void> _submit() async {
    final price = double.tryParse(_controller.text);
    if (price == null || price <= 0) return;

    setState(() => _submitting = true);
    try {
      await ref.read(itemsRepositoryProvider).updatePlatePrice(price: price);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Plate price updated.')));
      setState(() => _future = ref.read(itemsRepositoryProvider).platePrice());
    } catch (e) {
      if (!mounted) return;
      final message = e is ApiException ? e.message : 'Something went wrong.';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<double>(
      future: _future,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Current plate price',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              Text(
                CurrencyFormatter.format(snapshot.data!),
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _controller,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'New price'),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _submitting ? null : _submit,
                child: _submitting
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Update price'),
              ),
            ],
          ),
        );
      },
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
