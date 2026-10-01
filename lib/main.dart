import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'controllers/app_controller.dart';
import 'screens/home_shell.dart';
import 'services/drive_backup_service.dart';
import 'services/local_storage_service.dart';
import 'services/notification_service.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  final notifications = NotificationService();
  final driveBackup = DriveBackupService();
  final controller = await AppController.create(
    LocalStorageService(),
    notifications,
    driveBackup,
  );

  // Render the first Flutter frame before optional services such as
  // Google Sign-In or notifications initialize. A slow Google service on a
  // physical device must never leave the app stuck on the Android splash.
  runApp(BudgetTrackerApp(controller: controller));
  unawaited(controller.finishStartup());
}

class BudgetTrackerApp extends StatefulWidget {
  final AppController controller;

  const BudgetTrackerApp({super.key, required this.controller});

  @override
  State<BudgetTrackerApp> createState() => _BudgetTrackerAppState();
}

class _BudgetTrackerAppState extends State<BudgetTrackerApp>
    with WidgetsBindingObserver {
  late ThemeMode _themeMode;

  @override
  void initState() {
    super.initState();
    _themeMode = widget.controller.themeMode;
    WidgetsBinding.instance.addObserver(this);
    widget.controller.addListener(_syncTheme);
  }

  @override
  void didUpdateWidget(covariant BudgetTrackerApp oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_syncTheme);
      _themeMode = widget.controller.themeMode;
      widget.controller.addListener(_syncTheme);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(widget.controller.processRecurringTransactions());
      unawaited(widget.controller.maybeAutoBackup());
    }
  }

  void _syncTheme() {
    final next = widget.controller.themeMode;
    if (next != _themeMode && mounted) {
      setState(() => _themeMode = next);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.controller.removeListener(_syncTheme);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Budget Tracker',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: _themeMode,
      home: HomeShell(controller: widget.controller),
    );
  }
}
