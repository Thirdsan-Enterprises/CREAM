import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/api/repositories/customers_repository.dart';
import '../../core/api/repositories/stores_repository.dart';
import '../../core/auth/auth_session.dart';
import '../../core/auth/store.dart';
import '../../core/auth/user.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/formatters/currency_formatter.dart';
import '../../shared/formatters/date_formatter.dart';
import '../../shared/formatters/ledger_labels.dart';
import '../../shared/models/customer.dart';
import '../../shared/widgets/reason_dialog.dart';

const _accountTypeFilters = <String?>[null, 'prepaid', 'credit', 'lpo'];
const _accountTypeLabels = {
  null: 'All',
  'prepaid': 'Prepaid',
  'credit': 'Credit',
  'lpo': 'LPO',
};

/// Customer accounts, for a branch (its own customers) or the owner (every
/// branch, following the branch switcher). Search, accounts needing
/// attention, new accounts, deposits, statements, and corrections with a
/// reason.
class CustomersView extends ConsumerStatefulWidget {
  const CustomersView({super.key, required this.owner});

  final bool owner;

  @override
  ConsumerState<CustomersView> createState() => _CustomersViewState();
}

class _CustomersViewState extends ConsumerState<CustomersView> {
  final _controller = TextEditingController();
  List<Customer> _results = [];
  bool _searching = true;
  String? _error;
  String? _accountTypeFilter;
  bool _attentionOnly = false;
  int _searchToken = 0;

  @override
  void initState() {
    super.initState();
    // Load everyone up front so the list is browsable, not just searchable.
    _search();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final token = ++_searchToken;
    setState(() {
      _searching = true;
      _error = null;
    });
    try {
      final results = await ref
          .read(customersRepositoryProvider)
          .search(
            _controller.text.trim(),
            accountType: _accountTypeFilter,
            storeId: widget.owner ? ref.read(selectedStoreIdProvider) : null,
            attention: _attentionOnly,
          );
      if (mounted && token == _searchToken) {
        setState(() => _results = results);
      }
    } catch (e) {
      if (mounted && token == _searchToken) {
        setState(
          () => _error = e is ApiException
              ? e.message
              : 'Could not load customers.',
        );
      }
    } finally {
      if (mounted && token == _searchToken) {
        setState(() => _searching = false);
      }
    }
  }

  Future<void> _openCustomer(Customer customer) async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => CustomerDetailSheet(customer: customer),
    );
    if (changed == true) _search();
  }

  Future<void> _createCustomer() async {
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => NewCustomerSheet(owner: widget.owner),
    );
    if (created == true) _search();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.owner) {
      ref.listen(selectedStoreIdProvider, (_, _) => _search());
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Column(
            children: [
              TextField(
                controller: _controller,
                decoration: const InputDecoration(
                  labelText: 'Search by name or phone',
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (_) => _search(),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 40,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        avatar: const Icon(Icons.warning_amber, size: 18),
                        label: const Text('Needs attention'),
                        selected: _attentionOnly,
                        onSelected: (v) {
                          _attentionOnly = v;
                          _search();
                        },
                      ),
                    ),
                    for (final type in _accountTypeFilters)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(_accountTypeLabels[type]!),
                          selected: _accountTypeFilter == type,
                          showCheckmark: false,
                          onSelected: (_) {
                            _accountTypeFilter = type;
                            _search();
                          },
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Expanded(child: _body()),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createCustomer,
        icon: const Icon(Icons.person_add_alt),
        label: const Text('New customer'),
      ),
    );
  }

  Widget _body() {
    if (_searching && _results.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!),
            const SizedBox(height: 12),
            FilledButton(onPressed: _search, child: const Text('Retry')),
          ],
        ),
      );
    }
    if (_results.isEmpty) {
      return Center(
        child: Text(
          _attentionOnly
              ? 'No accounts are near their limit.'
              : 'No customers found.',
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _search,
      child: ListView.builder(
        padding: const EdgeInsets.only(bottom: 96),
        itemCount: _results.length,
        itemBuilder: (context, index) => CustomerTile(
          customer: _results[index],
          showBranch: widget.owner,
          onTap: () => _openCustomer(_results[index]),
        ),
      ),
    );
  }
}

Color _statusColor(String status) => switch (status) {
  'blocked' => AppColors.danger,
  'low' => const Color(0xFFB7791F),
  _ => AppColors.success,
};

/// A small pill: "Near limit" / "At limit" / "Used up".
class StandingBadge extends StatelessWidget {
  const StandingBadge({super.key, required this.customer});

  final Customer customer;

  @override
  Widget build(BuildContext context) {
    final standing = customer.standing;
    if (standing == null || standing.status == 'ok') {
      return const SizedBox.shrink();
    }
    final label = switch (standing.status) {
      'blocked' => customer.isCredit ? 'At limit' : 'Used up',
      _ => customer.isCredit ? 'Near limit' : 'Low',
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: _statusColor(standing.status),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

/// One row: name, phone, branch (owner), type, balance and a warning pill.
class CustomerTile extends StatelessWidget {
  const CustomerTile({
    super.key,
    required this.customer,
    required this.onTap,
    this.showBranch = false,
  });

  final Customer customer;
  final VoidCallback onTap;
  final bool showBranch;

  @override
  Widget build(BuildContext context) {
    final balance = customer.standing?.balance ?? customer.balance;
    final owes = (balance ?? 0) < 0;

    return Opacity(
      opacity: customer.isActive ? 1 : 0.5,
      child: Card(
        child: ListTile(
          onTap: onTap,
          title: Text(customer.name),
          subtitle: Text(
            [
              customer.phone,
              customer.isCredit
                  ? 'Credit, limit ${CurrencyFormatter.format(customer.creditLimit)}'
                  : customer.accountTypeLabel,
              if (showBranch) customer.storeName ?? 'All branches',
              if (!customer.isActive) 'Closed',
            ].join(' · '),
          ),
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                balance == null ? '—' : CurrencyFormatter.format(balance),
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: owes ? AppColors.danger : null,
                ),
              ),
              const SizedBox(height: 4),
              StandingBadge(customer: customer),
            ],
          ),
        ),
      ),
    );
  }
}

/// A banner explaining an account warning, used on the Sell screen and the
/// customer's statement.
class StandingBanner extends StatelessWidget {
  const StandingBanner({super.key, required this.standing});

  final AccountStanding standing;

  @override
  Widget build(BuildContext context) {
    final warning = standing.warning;
    if (warning == null || standing.status == 'ok') {
      return const SizedBox.shrink();
    }
    final color = _statusColor(standing.status);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        border: Border.all(color: color),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            standing.isBlocked ? Icons.block : Icons.warning_amber,
            color: color,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              warning,
              style: TextStyle(color: color, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class NewCustomerSheet extends ConsumerStatefulWidget {
  const NewCustomerSheet({super.key, required this.owner});

  final bool owner;

  @override
  ConsumerState<NewCustomerSheet> createState() => _NewCustomerSheetState();
}

class _NewCustomerSheetState extends ConsumerState<NewCustomerSheet> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _limitController = TextEditingController();
  String _accountType = 'prepaid';
  int? _storeId;
  List<Store> _stores = [];
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.owner) {
      _storeId = ref.read(selectedStoreIdProvider);
      ref.read(storesRepositoryProvider).all().then((stores) {
        if (mounted) setState(() => _stores = stores);
      });
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _limitController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_nameController.text.trim().isEmpty ||
        _phoneController.text.trim().isEmpty) {
      setState(() => _error = 'Enter the name and phone number.');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ref
          .read(customersRepositoryProvider)
          .create(
            name: _nameController.text.trim(),
            phone: _phoneController.text.trim(),
            accountType: _accountType,
            creditLimit: _accountType == 'credit'
                ? (double.tryParse(_limitController.text) ?? 0)
                : 0,
            storeId: widget.owner ? _storeId : null,
          );
      if (!mounted) return;
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${_nameController.text.trim()} added.')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(
        () => _error = e is ApiException ? e.message : 'Something went wrong.',
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final branchName = ref.read(authSessionProvider).user?.store?.name;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        20,
        20,
        MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'New customer account',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            if (!widget.owner && branchName != null)
              Text(
                'A customer of $branchName.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            const SizedBox(height: 16),
            TextField(
              controller: _nameController,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Phone'),
            ),
            if (widget.owner) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<int?>(
                initialValue: _storeId,
                decoration: const InputDecoration(labelText: 'Branch'),
                items: [
                  const DropdownMenuItem<int?>(
                    value: null,
                    child: Text('All branches'),
                  ),
                  for (final store in _stores)
                    DropdownMenuItem<int?>(
                      value: store.id,
                      child: Text(store.name),
                    ),
                ],
                onChanged: (v) => setState(() => _storeId = v),
              ),
            ],
            const SizedBox(height: 16),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'prepaid', label: Text('Prepaid')),
                ButtonSegment(value: 'credit', label: Text('Credit')),
                ButtonSegment(value: 'lpo', label: Text('LPO')),
              ],
              selected: {_accountType},
              onSelectionChanged: (value) =>
                  setState(() => _accountType = value.first),
            ),
            if (_accountType == 'credit') ...[
              const SizedBox(height: 12),
              if (widget.owner)
                TextField(
                  controller: _limitController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: 'Credit limit',
                    prefixText: 'UGX ',
                    helperText: 'Staff are warned at 80% and stopped at 100%.',
                  ),
                )
              else
                const Text(
                  'The owner sets the credit limit. Until then the account '
                  'cannot be charged.',
                ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: AppColors.danger)),
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
                  : const Text('Create account'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Balance, warning, deposit, statement, and (for managers and the owner)
/// edits and corrections with a reason.
class CustomerDetailSheet extends ConsumerStatefulWidget {
  const CustomerDetailSheet({super.key, required this.customer});

  final Customer customer;

  @override
  ConsumerState<CustomerDetailSheet> createState() =>
      _CustomerDetailSheetState();
}

class _CustomerDetailSheetState extends ConsumerState<CustomerDetailSheet> {
  late Future<
    ({
      Customer customer,
      double balance,
      AccountStanding? standing,
      List<LedgerEntry> entries,
    })
  >
  _future;
  final _depositController = TextEditingController();
  final _referenceController = TextEditingController();
  bool _busy = false;
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<
    ({
      Customer customer,
      double balance,
      AccountStanding? standing,
      List<LedgerEntry> entries,
    })
  >
  _load() =>
      ref.read(customersRepositoryProvider).statement(widget.customer.id);

  void _reload() {
    _changed = true;
    setState(() => _future = _load());
  }

  User? get _user => ref.read(authSessionProvider).user;
  bool get _isOwner => _user?.role == UserRole.admin;
  bool get _canCorrect => _isOwner || _user?.role == UserRole.storeManager;

  void _toast(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));

  Future<void> _run(Future<void> Function() call, String done) async {
    setState(() => _busy = true);
    try {
      await call();
      if (!mounted) return;
      _toast(done);
      _reload();
    } catch (e) {
      if (!mounted) return;
      _toast(e is ApiException ? e.message : 'Something went wrong.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deposit() async {
    final amount = double.tryParse(_depositController.text);
    if (amount == null || amount <= 0) return;
    await _run(() async {
      await ref
          .read(customersRepositoryProvider)
          .deposit(
            widget.customer.id,
            amount,
            note: _referenceController.text.trim(),
          );
      _depositController.clear();
      _referenceController.clear();
    }, 'Deposit recorded.');
  }

  Future<void> _correctBalance(Customer customer, double balance) async {
    final amount = TextEditingController();
    final reason = TextEditingController();
    var adds = false;
    final result = await showDialog<(double, String)>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Correct the balance'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Now ${CurrencyFormatter.format(balance)}.'),
                const SizedBox(height: 8),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: false, label: Text('Take off')),
                    ButtonSegment(value: true, label: Text('Add')),
                  ],
                  selected: {adds},
                  onSelectionChanged: (v) =>
                      setDialogState(() => adds = v.first),
                ),
                TextField(
                  controller: amount,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: 'Amount',
                    prefixText: 'UGX ',
                  ),
                ),
                TextField(
                  controller: reason,
                  decoration: const InputDecoration(
                    labelText: 'Reason',
                    helperText: 'e.g. deposit entered twice',
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  final value = double.tryParse(amount.text);
                  if (value == null ||
                      value <= 0 ||
                      reason.text.trim().isEmpty) {
                    return;
                  }
                  Navigator.pop(context, (
                    adds ? value : -value,
                    reason.text.trim(),
                  ));
                },
                child: const Text('Save'),
              ),
            ],
          );
        },
      ),
    );
    if (result == null) return;
    await _run(
      () => ref
          .read(customersRepositoryProvider)
          .correctBalance(customer.id, result.$1, reason: result.$2),
      'Balance corrected.',
    );
  }

  Future<void> _editDetails(Customer customer) async {
    final name = TextEditingController(text: customer.name);
    final phone = TextEditingController(text: customer.phone);
    final limit = TextEditingController(
      text: customer.creditLimit.toStringAsFixed(0),
    );
    var type = customer.accountType;
    var storeId = customer.storeId;
    var active = customer.isActive;
    final stores = _isOwner
        ? await ref.read(storesRepositoryProvider).all()
        : <Store>[];
    if (!mounted) return;

    final fields = await showDialog<Map<String, Object?>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Edit ${customer.name}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  decoration: const InputDecoration(labelText: 'Name'),
                ),
                TextField(
                  controller: phone,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'Phone'),
                ),
                if (_isOwner) ...[
                  DropdownButtonFormField<String>(
                    initialValue: type,
                    decoration: const InputDecoration(
                      labelText: 'Account type',
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'prepaid',
                        child: Text('Prepaid'),
                      ),
                      DropdownMenuItem(value: 'credit', child: Text('Credit')),
                      DropdownMenuItem(value: 'lpo', child: Text('LPO')),
                    ],
                    onChanged: (v) => setDialogState(() => type = v ?? type),
                  ),
                  if (type == 'credit')
                    TextField(
                      controller: limit,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(
                        labelText: 'Credit limit',
                        prefixText: 'UGX ',
                      ),
                    ),
                  DropdownButtonFormField<int?>(
                    initialValue: storeId,
                    decoration: const InputDecoration(labelText: 'Branch'),
                    items: [
                      const DropdownMenuItem<int?>(
                        value: null,
                        child: Text('All branches'),
                      ),
                      for (final store in stores)
                        DropdownMenuItem<int?>(
                          value: store.id,
                          child: Text(store.name),
                        ),
                    ],
                    onChanged: (v) => setDialogState(() => storeId = v),
                  ),
                ],
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Account open'),
                  value: active,
                  onChanged: (v) => setDialogState(() => active = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final newLimit = double.tryParse(limit.text);
                Navigator.pop(context, <String, Object?>{
                  if (name.text.trim() != customer.name)
                    'name': name.text.trim(),
                  if (phone.text.trim() != customer.phone)
                    'phone': phone.text.trim(),
                  if (active != customer.isActive) 'is_active': active,
                  if (_isOwner && type != customer.accountType)
                    'account_type': type,
                  if (_isOwner &&
                      type == 'credit' &&
                      newLimit != null &&
                      newLimit != customer.creditLimit)
                    'credit_limit': newLimit,
                  if (_isOwner && storeId != customer.storeId)
                    'store_id': storeId,
                });
              },
              child: const Text('Next'),
            ),
          ],
        ),
      ),
    );
    if (fields == null || fields.isEmpty || !mounted) return;

    final reason = await askReason(context, 'Why is this changing?');
    if (reason == null) return;
    await _run(
      () => ref
          .read(customersRepositoryProvider)
          .update(customer.id, fields, reason: reason),
      'Saved.',
    );
  }

  @override
  void dispose() {
    _depositController.dispose();
    _referenceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return FutureBuilder(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return const Center(child: Text('Could not load the account.'));
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final data = snapshot.data!;
            final customer = data.customer;
            final standing = data.standing;
            final theme = Theme.of(context);

            return ListView(
              controller: scrollController,
              padding: const EdgeInsets.all(20),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        customer.name,
                        style: theme.textTheme.headlineSmall,
                      ),
                    ),
                    if (_canCorrect)
                      PopupMenuButton<String>(
                        tooltip: 'More',
                        onSelected: (value) => switch (value) {
                          'edit' => _editDetails(customer),
                          _ => _correctBalance(customer, data.balance),
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(
                            value: 'edit',
                            child: Text('Edit details'),
                          ),
                          PopupMenuItem(
                            value: 'correct',
                            child: Text('Correct the balance'),
                          ),
                        ],
                      ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(_changed),
                    ),
                  ],
                ),
                Text(
                  [
                    customer.phone,
                    customer.accountTypeLabel,
                    customer.storeName ?? 'All branches',
                    if (!customer.isActive) 'Closed',
                  ].join(' · '),
                ),
                const SizedBox(height: 16),
                _BalanceCard(
                  customer: customer,
                  balance: data.balance,
                  standing: standing,
                ),
                if (standing != null && standing.status != 'ok') ...[
                  const SizedBox(height: 12),
                  StandingBanner(standing: standing),
                ],
                const SizedBox(height: 20),
                Text(
                  customer.isCredit ? 'Record a payment' : 'Top up',
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _referenceController,
                  decoration: InputDecoration(
                    labelText: customer.isLpo
                        ? 'LPO reference/number (optional)'
                        : 'Reference/note (optional)',
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _depositController,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        decoration: const InputDecoration(
                          labelText: 'Amount',
                          prefixText: 'UGX ',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: _busy ? null : _deposit,
                      child: _busy
                          ? const SizedBox(
                              height: 16,
                              width: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Save'),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Text('Statement', style: theme.textTheme.titleMedium),
                if (data.entries.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Text('No activity yet.'),
                  ),
                for (final entry in data.entries)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      '${ledgerEntryLabel(entry.type)} · ${CurrencyFormatter.format(entry.amount)}',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: entry.amount < 0 ? AppColors.danger : null,
                      ),
                    ),
                    subtitle: Text(
                      [
                        DateFormatter.dateTime(entry.occurredAt),
                        ?entry.recordedByName,
                        if (entry.note != null && entry.note!.isNotEmpty)
                          entry.note!,
                      ].join(' · '),
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }
}

/// Balance, and for a credit account how much of the limit is used.
class _BalanceCard extends StatelessWidget {
  const _BalanceCard({
    required this.customer,
    required this.balance,
    required this.standing,
  });

  final Customer customer;
  final double balance;
  final AccountStanding? standing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final used = standing?.creditUsedPct;
    final color = _statusColor(standing?.status ?? 'ok');

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        balance < 0 ? 'Owes' : 'Balance',
                        style: theme.textTheme.labelLarge,
                      ),
                      Text(
                        CurrencyFormatter.format(balance.abs()),
                        style: theme.textTheme.headlineMedium?.copyWith(
                          color: balance < 0 ? AppColors.danger : null,
                        ),
                      ),
                    ],
                  ),
                ),
                if (standing != null)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('Can spend', style: theme.textTheme.labelLarge),
                      Text(
                        CurrencyFormatter.format(standing!.available),
                        style: theme.textTheme.titleLarge?.copyWith(
                          color: color,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
            if (customer.isCredit && used != null) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: (used / 100).clamp(0, 1).toDouble(),
                  minHeight: 8,
                  color: color,
                  backgroundColor: color.withValues(alpha: 0.15),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${used.toStringAsFixed(0)}% of the ${CurrencyFormatter.format(customer.creditLimit)} limit used',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
