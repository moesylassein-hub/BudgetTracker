import 'package:flutter/material.dart';

import '../controllers/app_controller.dart';
import '../utils/currencies.dart';
import '../utils/formatters.dart';
import 'categories.dart';

class SettingsScreen extends StatelessWidget {
  final AppController controller;

  const SettingsScreen({super.key, required this.controller});

  Future<void> _editBudget(BuildContext context) async {
    var budgetText = controller.monthlyBudget.toStringAsFixed(0);
    final value = await showDialog<double>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Monthly budget'),
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
            ...AppCurrencies.values.map(
              (currency) => RadioListTile<String>(
                value: currency.code,
                groupValue: controller.currencyCode,
                title: Text('${currency.code} • ${currency.name}'),
                subtitle: Text('Example: ${AppFormatters.money(1234.56, currencyCode: currency.code)}'),
                onChanged: (value) => Navigator.pop(sheetContext, value),
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
    if (value && !enabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Notification permission was not granted, so budget alerts remain off.')),
      );
    } else if (value) {
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
          'This permanently deletes saved transactions and goals, resets budgets and categories, and turns budget alerts off on this device.',
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
                'Budget Tracker stores transactions, goals, categories and preferences locally on your device. Receipt text recognition runs on-device. This build contains no account system, advertising SDK, analytics SDK, or cloud sync. Optional budget alerts use local device notifications only.',
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
                ],
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
                    subtitle: const Text('Delete transactions, goals, budgets and custom categories'),
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
                subtitle: Text('Version 1.1.0 • Built for Android'),
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
