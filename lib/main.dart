import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'controllers/app_controller.dart';
import 'screens/home_shell.dart';
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
  await notifications.initialize();
  final controller = await AppController.create(
    LocalStorageService(),
    notifications,
  );
  runApp(BudgetTrackerApp(controller: controller));
}

class BudgetTrackerApp extends StatefulWidget {
  final AppController controller;

  const BudgetTrackerApp({super.key, required this.controller});

  @override
  State<BudgetTrackerApp> createState() => _BudgetTrackerAppState();
}

class _BudgetTrackerAppState extends State<BudgetTrackerApp> {
  late ThemeMode _themeMode;

  @override
  void initState() {
    super.initState();
    _themeMode = widget.controller.themeMode;
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

  void _syncTheme() {
    final next = widget.controller.themeMode;
    if (next != _themeMode && mounted) {
      setState(() => _themeMode = next);
    }
  }

  @override
  void dispose() {
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
