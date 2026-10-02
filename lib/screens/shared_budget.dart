import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controllers/app_controller.dart';
import '../models/sheet_change.dart';
import '../utils/formatters.dart';

class SharedBudgetScreen extends StatefulWidget {
  final AppController controller;
  const SharedBudgetScreen({super.key, required this.controller});
  @override
  State<SharedBudgetScreen> createState() => _SharedBudgetScreenState();
}

class _SharedBudgetScreenState extends State<SharedBudgetScreen> {
  bool _busy = false;
  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _ask(String title, String label, {String? message}) async {
    final text = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (message != null) ...[Text(message), const SizedBox(height: 16)],
            TextField(
              controller: text,
              autofocus: true,
              decoration: InputDecoration(labelText: label),
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
              if (text.text.trim().isNotEmpty) {
                Navigator.pop(context, text.text.trim());
              }
            },
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    // Dialog teardown may still read the text controller during its animation.
    await Future<void>.delayed(const Duration(milliseconds: 250));
    text.dispose();
    return result;
  }

  String _describe(SheetChange change) {
    final value = change.value;
    if (value == null) return 'Deleted by ${change.author}';
    if (change.entity.startsWith('transaction:')) {
      return '${value['store']} · ${value['type']} · ${value['amount']} ${value['currencyCode']}\n${value['category']} · ${value['date']}\n${value['note']}\nEdited by ${change.author}';
    }
    return '${value['name'] ?? value['title'] ?? change.entity.split(':').last}\n${value['value'] ?? value.values.join(' · ')}\nEdited by ${change.author}';
  }

  Future<void> _resolve(String entity, List<SheetChange> versions) async {
    final choice = await showDialog<SheetChange>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Choose the version to keep'),
        content: SizedBox(
          width: 400,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Both edits were saved. Choose one, then make any additional corrections in the app.',
                ),
                for (final change in versions)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context, change),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(_describe(change)),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Later'),
          ),
        ],
      ),
    );
    if (choice != null && mounted) {
      await _run(() => widget.controller.resolveSharedConflict(entity, choice));
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final app = widget.controller;
      final disabled = _busy || app.sharedSyncBusy;
      return Scaffold(
        appBar: AppBar(title: const Text('Shared budget')),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              app.sharedBudgetName,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 12),
            if (_busy || app.sharedSyncBusy) const LinearProgressIndicator(),
            const SizedBox(height: 12),
            if (!app.sharedBudgetActive) ...[
              const Text(
                'Share a budget through Google Sheets. Each person signs in with their own Google account. Your personal budget stays on this phone.',
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('Create shared budget'),
                onPressed: disabled
                    ? null
                    : () async {
                        final name = await _ask(
                          'Create shared budget',
                          'Budget name',
                          message:
                              'This copies your current transactions, categories, budgets, goals and recurring entries to a new Sheet in your Google Drive. Your personal budget is kept separately.',
                        );
                        if (name != null && mounted) {
                          await _run(() => app.openSharedBudget(name: name));
                        }
                      },
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                icon: const Icon(Icons.link),
                label: const Text('Join shared budget'),
                onPressed: disabled
                    ? null
                    : () async {
                        final link = await _ask(
                          'Join shared budget',
                          'Google Sheets link',
                          message:
                              'Ask the owner to share the budget Sheet with your Google email as an Editor, then paste its link here.',
                        );
                        if (link != null && mounted) {
                          await _run(() => app.openSharedBudget(link: link));
                        }
                      },
              ),
            ] else ...[
              Text(
                'Google account: ${app.driveAccountEmail ?? 'Reconnect to sync'}',
              ),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Your display name'),
                subtitle: Text(
                  app.sharedDisplayName.isEmpty
                      ? 'Using your Google email'
                      : app.sharedDisplayName,
                ),
                trailing: const Icon(Icons.edit),
                onTap: disabled
                    ? null
                    : () async {
                        final name = await _ask(
                          'Your display name',
                          'Name',
                          message:
                              'Shown on your new additions and edits. Your Google email stays in the shared history.',
                        );
                        if (name != null && mounted) {
                          await _run(() => app.setSharedDisplayName(name));
                        }
                      },
              ),
              Text('${app.sharedPendingCount} changes waiting to sync'),
              Text(
                app.sharedLastSynced == null
                    ? 'Not synced yet'
                    : 'Last sync: ${AppFormatters.dateTime(app.sharedLastSynced!)}',
              ),
              if (app.sharedSyncError != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    app.sharedSyncError!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              FilledButton.icon(
                icon: const Icon(Icons.sync),
                label: const Text('Sync / reconnect Google'),
                onPressed: disabled
                    ? null
                    : () => _run(() => app.syncSharedBudget(interactive: true)),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                icon: const Icon(Icons.person_add_alt),
                label: const Text('Invite editor'),
                onPressed: disabled
                    ? null
                    : () async {
                        final email = await _ask(
                          'Invite an editor',
                          'Their Google email',
                          message:
                              'Google will email an invitation granting editing access to this budget Sheet.',
                        );
                        if (email != null && mounted) {
                          await _run(() async {
                            await app.inviteSharedEditor(email);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Invitation sent. Share the Sheet link so they can join in Budget Tracker.',
                                  ),
                                ),
                              );
                            }
                          });
                        }
                      },
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.copy),
                label: const Text('Copy Sheet link'),
                onPressed: () async {
                  await Clipboard.setData(
                    ClipboardData(text: app.sharedSheetUrl!),
                  );
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Link copied. Sharing permissions can also be managed in Google Sheets.',
                        ),
                      ),
                    );
                  }
                },
              ),
              const SizedBox(height: 12),
              const Text(
                'Add and edit entries normally in the app. Sync runs every 30 seconds while the app is open. Offline edits stay on this phone until syncing succeeds.',
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: disabled
                    ? null
                    : () async {
                        var discard = false;
                        if (app.sharedPendingCount > 0) {
                          final choice = await showDialog<String>(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text('Switch to personal budget?'),
                              content: const Text(
                                'Keep unsynced edits on this phone to upload later, or discard them. Your personal budget and changes already saved to the shared Sheet stay unchanged.',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(context),
                                  child: const Text('Cancel'),
                                ),
                                TextButton(
                                  onPressed: () =>
                                      Navigator.pop(context, 'discard'),
                                  child: const Text('Discard edits'),
                                ),
                                FilledButton(
                                  onPressed: () =>
                                      Navigator.pop(context, 'keep'),
                                  child: const Text('Switch and keep edits'),
                                ),
                              ],
                            ),
                          );
                          if (choice == null || !mounted) return;
                          discard = choice == 'discard';
                          if (discard) {
                            final confirmed = await showDialog<bool>(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: const Text('Discard unsynced edits?'),
                                content: const Text(
                                  'This permanently removes this phone?s unsynced additions, edits and deletions from this shared budget. It does not delete anything already saved to the shared Sheet or change your personal budget.',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.pop(context, false),
                                    child: const Text('Cancel'),
                                  ),
                                  FilledButton(
                                    onPressed: () =>
                                        Navigator.pop(context, true),
                                    child: const Text('Discard and switch'),
                                  ),
                                ],
                              ),
                            );
                            if (confirmed != true || !mounted) return;
                          }
                        }
                        await _run(
                          () => app.leaveSharedBudget(discardPending: discard),
                        );
                      },
                child: const Text('Switch to personal budget'),
              ),
              for (final entry in app.sharedConflicts.entries)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.warning_amber_rounded),
                    title: const Text('Conflicting edits'),
                    subtitle: Text(_describe(entry.value.last)),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: disabled
                        ? null
                        : () => _resolve(entry.key, entry.value),
                  ),
                ),
            ],
          ],
        ),
      );
    },
  );
}
