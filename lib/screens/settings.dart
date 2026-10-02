import 'package:flutter/material.dart';

import '../controllers/app_controller.dart';
import '../services/drive_backup_service.dart';
import '../services/export_service.dart';
import '../utils/budget_cycle.dart';
import '../utils/currencies.dart';
import '../utils/formatters.dart';
import 'categories.dart';
import 'import_transactions.dart';
import 'recurring_transactions.dart';
import 'shared_budget.dart';

class SettingsScreen extends StatelessWidget {
  final AppController controller;

  const SettingsScreen({super.key, required this.controller});

  Future<void> _editBudget(BuildContext context) async {
    var budgetText = controller.monthlyBudget.toStringAsFixed(0);
    final value = await showDialog<double>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Budget per cycle'),
        content: TextFormField(
          initialValue: budgetText,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: 'Budget',
            suffixText: controller.currencyCode,
          ),
          onChanged: (value) => budgetText = value,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final parsed = double.tryParse(budgetText.trim());
              if (parsed != null && parsed > 0) Navigator.pop(dialogContext, parsed);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (value != null) await controller.setMonthlyBudget(value);
  }

  Future<void> _pickBudgetCycleStartDay(BuildContext context) async {
    var selected = controller.budgetCycleStartDay;
    final value = await showDialog<int>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Budget cycle start day'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Choose the day your personal money month starts. For example, choose 25 if salary arrives on the 25th.',
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<int>(
                initialValue: selected,
                decoration: const InputDecoration(labelText: 'Start day'),
                items: [
                  for (var day = 1; day <= 31; day++)
                    DropdownMenuItem(value: day, child: Text('Day $day')),
                ],
                onChanged: (value) {
                  if (value != null) setDialogState(() => selected = value);
                },
              ),
              const SizedBox(height: 12),
              Builder(
                builder: (context) {
                  final previewStart = BudgetCycle.startFor(DateTime.now(), selected);
                  final previewEnd = BudgetCycle.endExclusiveFor(DateTime.now(), selected)
                      .subtract(const Duration(days: 1));
                  return Text(
                    'Preview: ${AppFormatters.dateRange(previewStart, previewEnd)}',
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                  );
                },
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, selected),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (value != null) await controller.setBudgetCycleStartDay(value);
  }

  Future<void> _connectDrive(BuildContext context) async {
    try {
      await controller.connectDriveBackup();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Google Drive connected and first backup saved.')),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not connect Google Drive: $error')),
        );
      }
    }
  }

  Future<void> _backupNow(BuildContext context) async {
    try {
      await controller.backupNow();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Backup saved to Google Drive.')),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Backup failed: $error')),
        );
      }
    }
  }

  Future<void> _restoreDriveBackup(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Restore latest backup?'),
        content: const Text(
          'This replaces the financial data currently stored on this device with the newest Budget Tracker backup in Google Drive.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Restore')),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final restored = await controller.restoreLatestDriveBackup();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(restored ? 'Latest Google Drive backup restored.' : 'No Google Drive backup was found.'),
        ),
      );
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Restore failed: $error')),
        );
      }
    }
  }

  Future<void> _exportExcel(BuildContext context) async {
    try {
      await const ExportService().shareExcel(
        transactions: controller.transactions,
        currencyCode: controller.currencyCode,
        budgetCycleStartDay: controller.budgetCycleStartDay,
      );
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Excel export failed: $error')),
        );
      }
    }
  }

  Future<void> _exportCsv(BuildContext context) async {
    try {
      await const ExportService().shareCsv(
        transactions: controller.transactions,
        currencyCode: controller.currencyCode,
        budgetCycleStartDay: controller.budgetCycleStartDay,
      );
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('CSV export failed: $error')),
        );
      }
    }
  }

  Future<void> _pickCurrency(BuildContext context) async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 18),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
              child: Text(
                'Display currency',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
              ),
            ),
            RadioGroup<String>(
              groupValue: controller.currencyCode,
              onChanged: (value) {
                if (value != null) Navigator.pop(sheetContext, value);
              },
              child: Column(
                children: [
                  ...AppCurrencies.values.map(
                    (currency) => RadioListTile<String>(
                      value: currency.code,
                      title: Text('${currency.code} • ${currency.name}'),
                      subtitle: Text(
                        'Example: ${AppFormatters.money(1234.56, currencyCode: currency.code)}',
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(
                'Changing currency changes how amounts are displayed. Existing amounts are not converted using exchange rates.',
                style: TextStyle(fontSize: 12, height: 1.4),
              ),
            ),
          ],
        ),
      ),
    );
    if (selected != null) await controller.setCurrencyCode(selected);
  }

  Future<void> _toggleAlerts(BuildContext context, bool value) async {
    final enabled = await controller.setBudgetAlertsEnabled(value);
    if (!context.mounted) return;
    if (value && enabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Budget alerts enabled at 50%, 80%, 100%, plus category limits.')),
      );
    }
  }

  Future<void> _clearData(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Clear all data?'),
        content: const Text(
          'This permanently deletes saved transactions, recurring rules and goals, resets budgets and categories, and turns budget alerts off on this device.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Clear data')),
        ],
      ),
    );
    if (confirmed == true) {
      await controller.clearAllData();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Local data cleared.')));
      }
    }
  }

  void _showPrivacy(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 0, 22, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Privacy by design', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
              const SizedBox(height: 12),
              const Text(
                'Budget Tracker stores transactions, recurring rules, goals, categories and preferences locally on your device. Receipt text recognition runs on-device. If you explicitly connect Google Drive, the app can also store private backup snapshots in its Google Drive app-data area. This build contains no advertising or analytics SDK. Optional budget alerts use local device notifications only.',
                style: TextStyle(height: 1.55),
              ),
              const SizedBox(height: 16),
              Text(
                'For Google Play, publish the included PRIVACY_POLICY.md at a public URL and use that URL in Play Console.',
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(onPressed: () => Navigator.pop(sheetContext), child: const Text('Got it')),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final currency = AppCurrencies.byCode(controller.currencyCode);
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 110),
          children: [
            const _SectionLabel('Money'),
            Card(
              child: Column(
                children: [
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
                    leading: const _SettingsIcon(Icons.account_balance_wallet_rounded),
                    title: const Text('Monthly budget', style: TextStyle(fontWeight: FontWeight.w800)),
                    subtitle: Text(AppFormatters.money(controller.monthlyBudget, currencyCode: controller.currencyCode)),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => _editBudget(context),
                  ),
                  const Divider(height: 1, indent: 76),
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
                    leading: const _SettingsIcon(Icons.date_range_rounded),
                    title: const Text('Budget cycle', style: TextStyle(fontWeight: FontWeight.w800)),
                    subtitle: Text(
                      'Starts on day ${controller.budgetCycleStartDay} • ${AppFormatters.dateRange(controller.currentCycleStart, controller.currentCycleEndExclusive.subtract(const Duration(days: 1)))}',
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => _pickBudgetCycleStartDay(context),
                  ),
                  const Divider(height: 1, indent: 76),
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
                    leading: const _SettingsIcon(Icons.currency_exchange_rounded),
                    title: const Text('Currency', style: TextStyle(fontWeight: FontWeight.w800)),
                    subtitle: Text('${currency.code} • ${currency.name}'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => _pickCurrency(context),
                  ),
                  const Divider(height: 1, indent: 76),
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
                    leading: const _SettingsIcon(Icons.category_rounded),
                    title: const Text('Categories & budgets', style: TextStyle(fontWeight: FontWeight.w800)),
                    subtitle: const Text('Custom categories, icons and category limits'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => CategoriesScreen(controller: controller)),
                    ),
                  ),
                  const Divider(height: 1, indent: 76),
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
                    leading: const _SettingsIcon(Icons.event_repeat_rounded),
                    title: const Text(
                      'Recurring transactions',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    subtitle: Text(
                      controller.activeRecurringCount == 0
                          ? 'Automate salary, allowance and regular bills'
                          : '${controller.activeRecurringCount} active recurring transaction${controller.activeRecurringCount == 1 ? '' : 's'}',
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => RecurringTransactionsScreen(
                          controller: controller,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            const _SectionLabel('Google Drive backup'),
            Card(
              child: ListTile(
                leading: const Icon(Icons.group_rounded),
                title: const Text('Shared budget'),
                subtitle: Text(controller.sharedBudgetActive
                    ? '${controller.sharedBudgetName} · ${controller.sharedPendingCount} pending changes'
                    : 'Invite people using their own Google accounts'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => SharedBudgetScreen(controller: controller),
                )),
              ),
            ),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: controller.driveBackupConnected
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const _SettingsIcon(Icons.cloud_done_outlined),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('Connected', style: TextStyle(fontWeight: FontWeight.w900)),
                                    Text(
                                      controller.driveAccountEmail ?? 'Google Drive',
                                      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          DropdownButtonFormField<BackupFrequency>(
                            initialValue: controller.backupFrequency,
                            decoration: const InputDecoration(
                              labelText: 'Automatic backup',
                              helperText: 'Backs up only when data changed and the app is active.',
                            ),
                            items: BackupFrequency.values
                                .map((item) => DropdownMenuItem(value: item, child: Text(item.label)))
                                .toList(),
                            onChanged: controller.backupInProgress
                                ? null
                                : (value) {
                                    if (value != null) controller.setBackupFrequency(value);
                                  },
                          ),
                          const SizedBox(height: 12),
                          Text(
                            controller.lastDriveBackupAt == null
                                ? 'No successful backup yet.'
                                : 'Last backup: ${AppFormatters.dateTime(controller.lastDriveBackupAt!)}',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 14),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              FilledButton.icon(
                                onPressed: controller.backupInProgress ? null : () => _backupNow(context),
                                icon: const Icon(Icons.cloud_upload_outlined),
                                label: const Text('Back up now'),
                              ),
                              OutlinedButton.icon(
                                onPressed: controller.backupInProgress ? null : () => _restoreDriveBackup(context),
                                icon: const Icon(Icons.restore_rounded),
                                label: const Text('Restore latest'),
                              ),
                              TextButton(
                                onPressed: controller.backupInProgress
                                    ? null
                                    : () => controller.disconnectDriveBackup(),
                                child: const Text('Disconnect'),
                              ),
                            ],
                          ),
                          if (controller.backupInProgress) ...[
                            const SizedBox(height: 12),
                            const LinearProgressIndicator(),
                          ],
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const _SettingsIcon(Icons.add_to_drive_outlined),
                              const SizedBox(width: 12),
                              const Expanded(
                                child: Text(
                                  'Keep a private copy of your Budget Tracker data in your Google Drive app-data area.',
                                  style: TextStyle(height: 1.4),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          if (controller.driveBackupConfigured)
                            FilledButton.icon(
                              onPressed: controller.backupInProgress ? null : () => _connectDrive(context),
                              icon: const Icon(Icons.login_rounded),
                              label: const Text('Connect Google Drive'),
                            )
                          else
                            const Text(
                              'Google Drive OAuth is not configured in this build. See README.md → Google Drive backup setup.',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                        ],
                      ),
              ),
            ),
            const SizedBox(height: 24),
            const _SectionLabel('Import data'),
            Card(
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 8,
                ),
                leading: const _SettingsIcon(Icons.move_to_inbox_rounded),
                title: const Text(
                  'Import CSV or Excel',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: const Text(
                  'Migrate transactions from Money Tracker by Paraga or another finance app',
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.push<void>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ImportTransactionsScreen(
                      controller: controller,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            const _SectionLabel('Export data'),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        _SettingsIcon(Icons.table_view_rounded),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Open your transactions in Excel or Google Sheets.',
                            style: TextStyle(height: 1.4, fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Exports are readable reports, not restore backups. Each row includes its budget-cycle range.',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.icon(
                          onPressed: () => _exportExcel(context),
                          icon: const Icon(Icons.grid_on_rounded),
                          label: const Text('Export Excel (.xlsx)'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => _exportCsv(context),
                          icon: const Icon(Icons.description_outlined),
                          label: const Text('Export CSV'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            const _SectionLabel('Alerts'),
            Card(
              child: SwitchListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                secondary: const _SettingsIcon(Icons.notifications_active_outlined),
                title: const Text('Budget alerts', style: TextStyle(fontWeight: FontWeight.w800)),
                subtitle: const Text('Optional alerts at 50%, 80%, 100% and when a category limit is exceeded'),
                value: controller.budgetAlertsEnabled,
                onChanged: (value) => _toggleAlerts(context, value),
              ),
            ),
            const SizedBox(height: 24),
            const _SectionLabel('Appearance'),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.fromLTRB(4, 2, 4, 10),
                      child: Text('Theme', style: TextStyle(fontWeight: FontWeight.w800)),
                    ),
                    SegmentedButton<ThemeMode>(
                      segments: const [
                        ButtonSegment(value: ThemeMode.system, icon: Icon(Icons.phone_android_rounded), label: Text('System')),
                        ButtonSegment(value: ThemeMode.light, icon: Icon(Icons.light_mode_rounded), label: Text('Light')),
                        ButtonSegment(value: ThemeMode.dark, icon: Icon(Icons.dark_mode_rounded), label: Text('Dark')),
                      ],
                      selected: {controller.themeMode},
                      onSelectionChanged: (selection) => controller.setThemeMode(selection.first),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            const _SectionLabel('Privacy & data'),
            Card(
              child: Column(
                children: [
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 5),
                    leading: const _SettingsIcon(Icons.shield_outlined),
                    title: const Text('Privacy', style: TextStyle(fontWeight: FontWeight.w800)),
                    subtitle: const Text('Local-first, no ads, no analytics'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => _showPrivacy(context),
                  ),
                  const Divider(height: 1, indent: 76),
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 5),
                    leading: _SettingsIcon(Icons.delete_outline_rounded, color: Theme.of(context).colorScheme.error),
                    title: Text('Clear local data', style: TextStyle(fontWeight: FontWeight.w800, color: Theme.of(context).colorScheme.error)),
                    subtitle: const Text('Delete transactions, recurring rules, goals, budgets and custom categories'),
                    onTap: () => _clearData(context),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            const _SectionLabel('About'),
            const Card(
              child: ListTile(
                contentPadding: EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                leading: _SettingsIcon(Icons.info_outline_rounded),
                title: Text('Budget Tracker', style: TextStyle(fontWeight: FontWeight.w800)),
                subtitle: Text('Version 1.0.0 • Built for Android'),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;

  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 9),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          fontSize: 12,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _SettingsIcon extends StatelessWidget {
  final IconData icon;
  final Color? color;

  const _SettingsIcon(this.icon, {this.color});

  @override
  Widget build(BuildContext context) {
    final resolved = color ?? Theme.of(context).colorScheme.primary;
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: resolved.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Icon(icon, color: resolved),
    );
  }
}
