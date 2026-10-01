import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../utils/formatters.dart';

class NotificationService {
  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  Future<void>? _initializationFuture;

  Future<void> initialize() {
    return _initializationFuture ??= _initialize();
  }

  Future<void> _initialize() async {
    const android = AndroidInitializationSettings('ic_stat_budget');
    const settings = InitializationSettings(android: android);
    await _plugin.initialize(settings: settings);
  }

  Future<bool> requestPermission() async {
    await initialize();
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return true;
    return await android.requestNotificationsPermission() ?? true;
  }

  Future<void> showBudgetThreshold({
    required int percent,
    required double spent,
    required double budget,
    required String currencyCode,
  }) async {
    final title = percent >= 100
        ? 'Monthly budget reached'
        : 'You’ve used $percent% of your budget';
    final body = '${AppFormatters.money(spent, currencyCode: currencyCode)} spent of '
        '${AppFormatters.money(budget, currencyCode: currencyCode)}.';
    await _show(title, body);
  }

  Future<void> showCategoryExceeded({
    required String category,
    required double spent,
    required double budget,
    required String currencyCode,
  }) async {
    await _show(
      '$category budget exceeded',
      '${AppFormatters.money(spent, currencyCode: currencyCode)} spent against a '
      '${AppFormatters.money(budget, currencyCode: currencyCode)} category budget.',
    );
  }

  Future<void> _show(String title, String body) async {
    await initialize();
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'budget_alerts',
        'Budget alerts',
        channelDescription: 'Optional alerts when monthly or category budgets are reached.',
        importance: Importance.high,
        priority: Priority.high,
      ),
    );
    await _plugin.show(
      id: DateTime.now().millisecondsSinceEpoch.remainder(2147483647),
      title: title,
      body: body,
      notificationDetails: details,
    );
  }
}
