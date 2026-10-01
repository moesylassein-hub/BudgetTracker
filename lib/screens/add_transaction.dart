import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controllers/app_controller.dart';
import '../models/receipt_scan_result.dart';
import '../models/transaction.dart';
import '../utils/app_categories.dart';
import '../utils/currencies.dart';
import '../utils/formatters.dart';
import 'scan_receipt.dart';

class AddTransactionScreen extends StatefulWidget {
  final AppController controller;
  final Transaction? transaction;
  final ReceiptScanResult? scanResult;
  final TransactionType initialType;

  const AddTransactionScreen({
    super.key,
    required this.controller,
    this.transaction,
    this.scanResult,
    this.initialType = TransactionType.expense,
  });

  @override
  State<AddTransactionScreen> createState() => _AddTransactionScreenState();
}

class _AddTransactionScreenState extends State<AddTransactionScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _storeController;
  late final TextEditingController _amountController;
  late final TextEditingController _noteController;
  late List<String> _ledgerOptions;
  late List<String> _accountOptions;
  late String _ledger;
  late String _account;
  late String _transactionCurrencyCode;
  late String _category;
  late DateTime _date;
  late TransactionType _type;

  bool get _isEditing => widget.transaction != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.transaction;
    final scan = widget.scanResult;
    _type = existing?.type ?? widget.initialType;
    _storeController = TextEditingController(text: existing?.store ?? scan?.store ?? '');
    final decimalDigits = AppCurrencies.byCode(widget.controller.currencyCode).decimalDigits;
    _amountController = TextEditingController(
      text: existing != null
          ? existing.amount.toStringAsFixed(decimalDigits)
          : scan?.amount?.toStringAsFixed(decimalDigits) ?? '',
    );
    _noteController = TextEditingController(text: existing?.note ?? _scanNote(scan));
    _ledger = existing?.ledger.trim() ?? '';
    _account = existing?.account.trim() ?? '';
    _ledgerOptions = _withCurrent(
      widget.controller.ledgerOptions,
      _ledger,
    );
    _accountOptions = _withCurrent(
      widget.controller.accountOptions,
      _account,
    );
    _transactionCurrencyCode =
        existing?.currencyCode.isNotEmpty == true
            ? existing!.currencyCode
            : scan?.currencyCode ?? widget.controller.currencyCode;
    _category = _resolveInitialCategory(existing?.category ?? scan?.category);
    _date = existing?.date ?? scan?.date ?? DateTime.now();
  }

  static const _addLedgerValue = '__add_new_ledger__';
  static const _addAccountValue = '__add_new_account__';

  List<String> _withCurrent(List<String> values, String current) {
    final result = <String>[];
    final seen = <String>{};
    for (final value in [...values, current]) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) continue;
      if (seen.add(trimmed.toLowerCase())) result.add(trimmed);
    }
    result.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return result;
  }

  String _addUniqueOption(List<String> options, String value) {
    final trimmed = value.trim();
    for (final option in options) {
      if (option.toLowerCase() == trimmed.toLowerCase()) return option;
    }
    options.add(trimmed);
    options.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return trimmed;
  }

  Future<String?> _askForNewOption({
    required String title,
    required String hint,
  }) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          maxLength: 50,
          decoration: InputDecoration(hintText: hint),
          onSubmitted: (value) {
            final trimmed = value.trim();
            if (trimmed.isNotEmpty) Navigator.pop(dialogContext, trimmed);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final trimmed = controller.text.trim();
              if (trimmed.isNotEmpty) Navigator.pop(dialogContext, trimmed);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result?.trim();
  }

  Future<void> _changeLedger(String? value) async {
    if (value == null) return;
    if (value != _addLedgerValue) {
      setState(() => _ledger = value);
      return;
    }

    final added = await _askForNewOption(
      title: 'Add ledger',
      hint: 'e.g. My Wallet',
    );
    if (!mounted) return;
    if (added == null || added.isEmpty) {
      setState(() {});
      return;
    }
    setState(() => _ledger = _addUniqueOption(_ledgerOptions, added));
  }

  Future<void> _changeAccount(String? value) async {
    if (value == null) return;
    if (value != _addAccountValue) {
      setState(() => _account = value);
      return;
    }

    final added = await _askForNewOption(
      title: 'Add account',
      hint: 'e.g. Cash',
    );
    if (!mounted) return;
    if (added == null || added.isEmpty) {
      setState(() {});
      return;
    }
    setState(() => _account = _addUniqueOption(_accountOptions, added));
  }

  String _scanNote(ReceiptScanResult? scan) {
    if (scan == null) return '';
    final parts = <String>[];
    if (scan.taxAmount != null) {
      parts.add('Receipt tax: ${AppFormatters.money(scan.taxAmount!, currencyCode: scan.currencyCode ?? widget.controller.currencyCode)}');
    }
    if (scan.receiptNumber != null) parts.add('Receipt #${scan.receiptNumber}');
    return parts.join(' • ');
  }

  String _resolveInitialCategory(String? preferred) {
    final available = widget.controller.categoriesForType(_type);
    if (preferred != null && available.any((item) => item.name == preferred)) {
      return preferred;
    }
    return widget.controller.fallbackCategory(_type);
  }

  @override
  void dispose() {
    _storeController.dispose();
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final result = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (result != null && mounted) setState(() => _date = result);
  }

  Future<void> _scanReceipt() async {
    final result = await Navigator.of(context).push<ReceiptScanResult>(
      MaterialPageRoute(
        builder: (_) => ScanReceiptScreen(
          preferredCurrencyCode: widget.controller.currencyCode,
        ),
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      _type = TransactionType.expense;
      _storeController.text = result.store;
      if (result.amount != null) _amountController.text = result.amount!.toStringAsFixed(2);
      _category = _resolveInitialCategory(result.category);
      _date = result.date ?? _date;
      if (result.currencyCode != null && result.currencyCode!.isNotEmpty) {
        _transactionCurrencyCode = result.currencyCode!.toUpperCase();
      }
      final note = _scanNote(result);
      if (note.isNotEmpty && _noteController.text.trim().isEmpty) _noteController.text = note;
    });
  }

  void _changeType(TransactionType type) {
    if (_type == type) return;
    setState(() {
      _type = type;
      _category = widget.controller.fallbackCategory(type);
    });
  }

  void _save() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final amount = double.parse(_amountController.text.trim());
    final transaction = Transaction(
      id: widget.transaction?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
      store: _storeController.text.trim(),
      amount: amount,
      category: _category,
      date: _date,
      note: _noteController.text.trim(),
      ledger: _ledger,
      account: _account,
      currencyCode: _transactionCurrencyCode.trim().toUpperCase(),
      type: _type,
    );
    Navigator.pop(context, transaction);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final categories = widget.controller.categoriesForType(_type);
    final currency = AppCurrencies.byCode(_transactionCurrencyCode);
    final isExpense = _type == TransactionType.expense;
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit transaction' : 'Add transaction'),
        actions: [
          TextButton(onPressed: _save, child: const Text('Save')),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
            children: [
              SegmentedButton<TransactionType>(
                segments: const [
                  ButtonSegment(
                    value: TransactionType.expense,
                    icon: Icon(Icons.arrow_upward_rounded),
                    label: Text('Expense'),
                  ),
                  ButtonSegment(
                    value: TransactionType.income,
                    icon: Icon(Icons.arrow_downward_rounded),
                    label: Text('Income'),
                  ),
                ],
                selected: {_type},
                onSelectionChanged: (selection) => _changeType(selection.first),
              ),
              if (isExpense) ...[
                const SizedBox(height: 18),
                InkWell(
                  onTap: _scanReceipt,
                  borderRadius: BorderRadius.circular(22),
                  child: Ink(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: scheme.primary,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Icon(Icons.document_scanner_rounded, color: scheme.onPrimary),
                        ),
                        const SizedBox(width: 14),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Scan a receipt', style: TextStyle(fontWeight: FontWeight.w800)),
                              SizedBox(height: 3),
                              Text('Detect merchant, total, date, currency and tax.'),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right_rounded),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              Text(
                isExpense ? 'Expense details' : 'Income details',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _storeController,
                textInputAction: TextInputAction.next,
                textCapitalization: TextCapitalization.words,
                maxLength: 60,
                decoration: InputDecoration(
                  labelText: isExpense ? 'Merchant or description' : 'Source or description',
                  hintText: isExpense ? 'e.g. Carrefour' : 'e.g. Monthly salary',
                  prefixIcon: Icon(isExpense ? Icons.storefront_rounded : Icons.work_outline_rounded),
                  counterText: '',
                ),
                validator: (value) {
                  if (value == null || value.trim().length < 2) {
                    return isExpense ? 'Enter a merchant or description.' : 'Enter an income source.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _amountController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(
                    RegExp('^\\d{0,8}([.]\\d{0,${currency.decimalDigits}})?'),
                  ),
                ],
                decoration: InputDecoration(
                  labelText: 'Amount',
                  hintText: '0.00',
                  suffixText: currency.code,
                  prefixIcon: const Icon(Icons.payments_rounded),
                ),
                validator: (value) {
                  final amount = double.tryParse(value?.trim() ?? '');
                  if (amount == null || amount <= 0) return 'Enter a valid amount.';
                  if (amount > 99999999) return 'Amount is too large.';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: categories.any((item) => item.name == _category)
                    ? _category
                    : categories.isEmpty
                        ? null
                        : categories.first.name,
                decoration: const InputDecoration(
                  labelText: 'Category',
                  prefixIcon: Icon(Icons.category_rounded),
                ),
                items: categories
                    .map(
                      (item) => DropdownMenuItem(
                        value: item.name,
                        child: Row(
                          children: [
                            Icon(AppCategories.iconForKey(item.iconKey), size: 20),
                            const SizedBox(width: 10),
                            Text(item.name),
                          ],
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) setState(() => _category = value);
                },
              ),
              const SizedBox(height: 12),
              InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: _pickDate,
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Date',
                    prefixIcon: Icon(Icons.calendar_month_rounded),
                    suffixIcon: Icon(Icons.expand_more_rounded),
                  ),
                  child: Text(AppFormatters.date(_date)),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: ValueKey(
                  'ledger-$_ledger-${_ledgerOptions.length}',
                ),
                initialValue: _ledger,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Ledger (optional)',
                  prefixIcon: Icon(Icons.account_balance_wallet_outlined),
                ),
                items: [
                  const DropdownMenuItem(
                    value: '',
                    child: Text('Not set'),
                  ),
                  ..._ledgerOptions.map(
                    (item) => DropdownMenuItem(
                      value: item,
                      child: Text(
                        item,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  const DropdownMenuItem(
                    value: _addLedgerValue,
                    child: Row(
                      children: [
                        Icon(Icons.add_rounded, size: 20),
                        SizedBox(width: 8),
                        Text('Add new ledger…'),
                      ],
                    ),
                  ),
                ],
                onChanged: _changeLedger,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: ValueKey(
                  'account-$_account-${_accountOptions.length}',
                ),
                initialValue: _account,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Account (optional)',
                  prefixIcon: Icon(Icons.account_balance_outlined),
                ),
                items: [
                  const DropdownMenuItem(
                    value: '',
                    child: Text('Not set'),
                  ),
                  ..._accountOptions.map(
                    (item) => DropdownMenuItem(
                      value: item,
                      child: Text(
                        item,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  const DropdownMenuItem(
                    value: _addAccountValue,
                    child: Row(
                      children: [
                        Icon(Icons.add_rounded, size: 20),
                        SizedBox(width: 8),
                        Text('Add new account…'),
                      ],
                    ),
                  ),
                ],
                onChanged: _changeAccount,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: AppCurrencies.values.any(
                  (item) => item.code == _transactionCurrencyCode,
                )
                    ? _transactionCurrencyCode
                    : widget.controller.currencyCode,
                decoration: const InputDecoration(
                  labelText: 'Currency',
                  prefixIcon: Icon(Icons.currency_exchange_rounded),
                ),
                items: AppCurrencies.values
                    .map(
                      (item) => DropdownMenuItem(
                        value: item.code,
                        child: Text('${item.code} • ${item.name}'),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _transactionCurrencyCode = value);
                  }
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _noteController,
                maxLines: 3,
                maxLength: 180,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Note (optional)',
                  hintText: 'Anything worth remembering?',
                  alignLabelWithHint: true,
                  prefixIcon: Padding(
                    padding: EdgeInsets.only(bottom: 54),
                    child: Icon(Icons.notes_rounded),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: _save,
                icon: Icon(_isEditing ? Icons.check_rounded : Icons.add_rounded),
                label: Text(_isEditing
                    ? 'Save changes'
                    : isExpense
                        ? 'Add expense'
                        : 'Add income'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
