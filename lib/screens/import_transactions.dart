// ignore_for_file: prefer_interpolation_to_compose_strings

import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../controllers/app_controller.dart';
import '../models/transaction.dart';
import '../services/import_service.dart';
import '../utils/formatters.dart';

class ImportTransactionsScreen extends StatefulWidget {
  final AppController controller;

  const ImportTransactionsScreen({
    super.key,
    required this.controller,
  });

  @override
  State<ImportTransactionsScreen> createState() =>
      _ImportTransactionsScreenState();
}

class _ImportTransactionsScreenState extends State<ImportTransactionsScreen> {
  static const _service = ImportService();

  ImportTable? _table;
  ImportMapping? _mapping;
  ImportPreview? _preview;
  String? _error;
  bool _picking = false;
  bool _importing = false;

  Future<void> _pickFile() async {
    if (_picking) return;
    setState(() {
      _picking = true;
      _error = null;
    });

    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: const ['csv', 'xlsx'],
      );
      if (file == null) return;

      final Uint8List bytes = await file.readAsBytes();
      final table = _service.readFile(
        fileName: file.name,
        bytes: bytes,
      );
      final mapping = _service.detectMapping(table);

      if (!mounted) return;
      setState(() {
        _table = table;
        _mapping = mapping;
        _preview = null;
        _error = null;
      });
      _buildPreview();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  void _buildPreview() {
    final table = _table;
    final mapping = _mapping;
    if (table == null || mapping == null) return;

    try {
      final preview = _service.preview(
        table: table,
        mapping: mapping,
        existingTransactions: widget.controller.transactions,
      );
      setState(() {
        _preview = preview;
        _error = null;
      });
    } catch (error) {
      setState(() {
        _preview = null;
        _error = error.toString();
      });
    }
  }

  void _setMapping(_MappingField field, int? value) {
    final current = _mapping;
    if (current == null) return;
    setState(() {
      _mapping = ImportMapping(
        date: field == _MappingField.date ? value : current.date,
        description: field == _MappingField.description
            ? value
            : current.description,
        category:
            field == _MappingField.category ? value : current.category,
        subCategory: field == _MappingField.subCategory
            ? value
            : current.subCategory,
        ledger: field == _MappingField.ledger ? value : current.ledger,
        account: field == _MappingField.account ? value : current.account,
        note: field == _MappingField.note ? value : current.note,
        amount: field == _MappingField.amount ? value : current.amount,
        incomeAmount: field == _MappingField.income
            ? value
            : current.incomeAmount,
        expenseAmount: field == _MappingField.expense
            ? value
            : current.expenseAmount,
        type: field == _MappingField.type ? value : current.type,
        wallet: current.wallet,
        currency:
            field == _MappingField.currency ? value : current.currency,
        labels: current.labels,
      );
      _preview = null;
    });
    _buildPreview();
  }

  Future<void> _import() async {
    final preview = _preview;
    if (preview == null || preview.ready.isEmpty || _importing) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          'Import ' +
              preview.ready.length.toString() +
              (preview.ready.length == 1
                  ? ' transaction?'
                  : ' transactions?'),
        ),
        content: const Text(
          'Imported transactions become normal Budget Tracker activity. '
          'New category names will be created automatically.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Import'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _importing = true);
    try {
      await widget.controller.importTransactions(preview.ready);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            preview.ready.length.toString() +
                (preview.ready.length == 1
                    ? ' transaction imported.'
                    : ' transactions imported.'),
          ),
        ),
      );
      Navigator.pop(context);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = 'Import failed: ' + error.toString());
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  bool _hasCurrencyWarning(ImportPreview preview) {
    if (preview.sourceCurrencies.isEmpty) return false;
    if (preview.sourceCurrencies.length > 1) return true;
    return preview.sourceCurrencies.single.toUpperCase() !=
        widget.controller.currencyCode.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final table = _table;
    final preview = _preview;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Import transactions'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
        children: [
          _IntroCard(onPick: _picking ? null : _pickFile),
          if (_error != null) ...[
            const SizedBox(height: 12),
            _ErrorCard(message: _error!),
          ],
          if (table != null) ...[
            const SizedBox(height: 18),
            _FileCard(table: table),
            const SizedBox(height: 18),
            _MappingCard(
              table: table,
              mapping: _mapping!,
              onChanged: _setMapping,
            ),
          ],
          if (preview != null) ...[
            const SizedBox(height: 18),
            _PreviewSummary(preview: preview),
            if (_hasCurrencyWarning(preview)) ...[
              const SizedBox(height: 12),
              _CurrencyWarning(
                currencies: preview.sourceCurrencies,
                appCurrency: widget.controller.currencyCode,
              ),
            ],
            if (preview.ready.isNotEmpty) ...[
              const SizedBox(height: 18),
              _PreviewTransactions(
                transactions: preview.ready.take(5).toList(),
                currencyCode: widget.controller.currencyCode,
              ),
            ],
            if (preview.warnings.isNotEmpty) ...[
              const SizedBox(height: 18),
              _WarningCard(warnings: preview.warnings),
            ],
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed:
                  preview.ready.isEmpty || _importing ? null : _import,
              icon: _importing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.download_done_rounded),
              label: Text(
                preview.ready.isEmpty
                    ? 'Nothing to import'
                    : 'Import ' +
                        preview.ready.length.toString() +
                        ' transactions',
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _IntroCard extends StatelessWidget {
  final VoidCallback? onPick;

  const _IntroCard({required this.onPick});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    Icons.move_to_inbox_rounded,
                    color: scheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Bring your history from another money app',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Supports CSV and Excel (.xlsx), including Money Tracker by '
              'Paraga Mobile and ledger/account exports. Nothing is saved '
              'until you review the preview.',
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: onPick,
              icon: const Icon(Icons.folder_open_rounded),
              label: const Text('Choose CSV or Excel file'),
            ),
          ],
        ),
      ),
    );
  }
}

class _FileCard extends StatelessWidget {
  final ImportTable table;

  const _FileCard({required this.table});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  table.looksLikeParagaMoneyTracker
                      ? Icons.verified_rounded
                      : Icons.description_outlined,
                  color: table.looksLikeParagaMoneyTracker
                      ? scheme.primary
                      : scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    table.fileName,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
              ],
            ),
            if (table.sheetName != null) ...[
              const SizedBox(height: 5),
              Text(
                'Sheet: ' + table.sheetName!,
                style: TextStyle(
                  color: scheme.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
            ],
            const SizedBox(height: 8),
            Text(
              table.looksLikeParagaMoneyTracker
                  ? 'Money Tracker (Paraga) format detected. Column mapping was filled automatically.'
                  : 'Columns were detected automatically. Check the mapping before importing.',
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              table.rows.length.toString() + ' data rows found',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    );
  }
}

class _MappingCard extends StatelessWidget {
  final ImportTable table;
  final ImportMapping mapping;
  final void Function(_MappingField field, int? value) onChanged;

  const _MappingCard({
    required this.table,
    required this.mapping,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Column mapping',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              'With a Type column, negative expenses are refunds. Without Type, '
              'negative amounts are spending and positive amounts are income. Use '
              'Income amount and Expense amount when the export splits them.',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 12,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 14),
            _ColumnDropdown(
              label: 'Date',
              value: mapping.date,
              headers: table.headers,
              isRequired: true,
              onChanged: (value) => onChanged(_MappingField.date, value),
            ),
            const SizedBox(height: 10),
            _ColumnDropdown(
              label: 'Remark / merchant',
              value: mapping.description,
              headers: table.headers,
              onChanged: (value) =>
                  onChanged(_MappingField.description, value),
            ),
            const SizedBox(height: 10),
            _ColumnDropdown(
              label: 'Category',
              value: mapping.category,
              headers: table.headers,
              onChanged: (value) =>
                  onChanged(_MappingField.category, value),
            ),
            const SizedBox(height: 10),
            _ColumnDropdown(
              label: 'Sub-category → Note',
              value: mapping.subCategory,
              headers: table.headers,
              onChanged: (value) =>
                  onChanged(_MappingField.subCategory, value),
            ),
            const SizedBox(height: 10),
            _ColumnDropdown(
              label: 'Ledger',
              value: mapping.ledger,
              headers: table.headers,
              onChanged: (value) =>
                  onChanged(_MappingField.ledger, value),
            ),
            const SizedBox(height: 10),
            _ColumnDropdown(
              label: 'Account',
              value: mapping.account,
              headers: table.headers,
              onChanged: (value) =>
                  onChanged(_MappingField.account, value),
            ),
            const SizedBox(height: 10),
            _ColumnDropdown(
              label: 'Currency',
              value: mapping.currency,
              headers: table.headers,
              onChanged: (value) =>
                  onChanged(_MappingField.currency, value),
            ),
            const SizedBox(height: 10),
            _ColumnDropdown(
              label: 'Note',
              value: mapping.note,
              headers: table.headers,
              onChanged: (value) =>
                  onChanged(_MappingField.note, value),
            ),
            const SizedBox(height: 10),
            _ColumnDropdown(
              label: 'Type',
              value: mapping.type,
              headers: table.headers,
              onChanged: (value) => onChanged(_MappingField.type, value),
            ),
            const Divider(height: 28),
            _ColumnDropdown(
              label: 'Signed amount',
              value: mapping.amount,
              headers: table.headers,
              onChanged: (value) =>
                  onChanged(_MappingField.amount, value),
            ),
            const SizedBox(height: 10),
            _ColumnDropdown(
              label: 'Income amount',
              value: mapping.incomeAmount,
              headers: table.headers,
              onChanged: (value) =>
                  onChanged(_MappingField.income, value),
            ),
            const SizedBox(height: 10),
            _ColumnDropdown(
              label: 'Expense amount',
              value: mapping.expenseAmount,
              headers: table.headers,
              onChanged: (value) =>
                  onChanged(_MappingField.expense, value),
            ),
          ],
        ),
      ),
    );
  }
}

class _ColumnDropdown extends StatelessWidget {
  final String label;
  final int? value;
  final List<String> headers;
  final bool isRequired;
  final ValueChanged<int?> onChanged;

  const _ColumnDropdown({
    required this.label,
    required this.value,
    required this.headers,
    required this.onChanged,
    this.isRequired = false,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<int>(
      initialValue: value ?? -1,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: isRequired ? label + ' *' : label,
      ),
      items: [
        const DropdownMenuItem<int>(
          value: -1,
          child: Text('Not used'),
        ),
        for (var i = 0; i < headers.length; i++)
          DropdownMenuItem<int>(
            value: i,
            child: Text(
              headers[i].isEmpty ? 'Column ' + (i + 1).toString() : headers[i],
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      onChanged: (selected) =>
          onChanged(selected == null || selected < 0 ? null : selected),
    );
  }
}

class _PreviewSummary extends StatelessWidget {
  final ImportPreview preview;

  const _PreviewSummary({required this.preview});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _SummaryChip(
              icon: Icons.check_circle_outline_rounded,
              label: 'Ready',
              value: preview.ready.length,
            ),
            _SummaryChip(
              icon: Icons.copy_all_outlined,
              label: 'Duplicates',
              value: preview.duplicateCount,
            ),
            _SummaryChip(
              icon: Icons.swap_horiz_rounded,
              label: 'Transfers skipped',
              value: preview.transferCount,
            ),
            _SummaryChip(
              icon: Icons.error_outline_rounded,
              label: 'Invalid',
              value: preview.invalidCount,
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final int value;

  const _SummaryChip({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Icon(icon, size: 18),
      label: Text(
        label + ': ' + value.toString(),
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _PreviewTransactions extends StatelessWidget {
  final List<Transaction> transactions;
  final String currencyCode;

  const _PreviewTransactions({
    required this.transactions,
    required this.currencyCode,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Column(
        children: [
          const ListTile(
            title: Text(
              'Preview',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
            subtitle: Text('First transactions that will be imported'),
          ),
          const Divider(height: 1),
          for (var i = 0; i < transactions.length; i++) ...[
            ListTile(
              leading: CircleAvatar(
                child: Icon(
                  transactions[i].isIncome
                      ? Icons.south_west_rounded
                      : Icons.north_east_rounded,
                  size: 18,
                ),
              ),
              title: Text(
                transactions[i].store,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: Text(
                transactions[i].category +
                    ' • ' +
                    AppFormatters.date(transactions[i].date),
              ),
              trailing: Text(
                (transactions[i].cashFlow >= 0 ? '+' : '-') +
                    AppFormatters.money(
                      transactions[i].amount.abs(),
                      currencyCode: currencyCode,
                    ),
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
            if (i != transactions.length - 1)
              const Divider(height: 1, indent: 72),
          ],
        ],
      ),
    );
  }
}

class _WarningCard extends StatefulWidget {
  final List<String> warnings;

  const _WarningCard({required this.warnings});

  @override
  State<_WarningCard> createState() => _WarningCardState();
}

class _WarningCardState extends State<_WarningCard> {
  bool _showAll = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final canCollapse = widget.warnings.length > 5;
    final visibleWarnings = _showAll || !canCollapse
        ? widget.warnings
        : widget.warnings.take(5).toList();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Rows that need attention (' +
                widget.warnings.length.toString() +
                ')',
            style: TextStyle(
              color: scheme.onErrorContainer,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          for (final warning in visibleWarnings)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '• ' + warning,
                style: TextStyle(color: scheme.onErrorContainer),
              ),
            ),
          if (canCollapse) ...[
            const SizedBox(height: 4),
            TextButton.icon(
              onPressed: () => setState(() => _showAll = !_showAll),
              style: TextButton.styleFrom(
                foregroundColor: scheme.onErrorContainer,
                padding: EdgeInsets.zero,
              ),
              icon: Icon(
                _showAll
                    ? Icons.expand_less_rounded
                    : Icons.expand_more_rounded,
              ),
              label: Text(
                _showAll
                    ? 'Show less'
                    : 'Show all ' +
                        widget.warnings.length.toString() +
                        ' rows',
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CurrencyWarning extends StatelessWidget {
  final Set<String> currencies;
  final String appCurrency;

  const _CurrencyWarning({
    required this.currencies,
    required this.appCurrency,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final source = currencies.toList()..sort();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.currency_exchange_rounded,
            color: scheme.onTertiaryContainer,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Source currency: ' +
                  source.join(', ') +
                  '. Budget Tracker currently displays ' +
                  appCurrency +
                  ' and does not convert exchange rates during import. '
                  'Original currency and wallet names are preserved in the note.',
              style: TextStyle(
                color: scheme.onTertiaryContainer,
                height: 1.4,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  final String message;

  const _ErrorCard({required this.message});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Text(
        message.replaceFirst('FormatException: ', ''),
        style: TextStyle(
          color: scheme.onErrorContainer,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

enum _MappingField {
  date,
  description,
  category,
  subCategory,
  ledger,
  account,
  currency,
  note,
  type,
  amount,
  income,
  expense,
}
