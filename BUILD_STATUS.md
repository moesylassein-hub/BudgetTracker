# Build status

This source has been updated to version 1.1.0+2. The current workspace does not contain the Flutter SDK or Android SDK, so an actual `flutter analyze`, `flutter test`, Android run, or signed AAB build could not be executed here.

File-level checks completed in this workspace include Dart import-path validation, basic delimiter validation, YAML parsing, Android XML parsing, package/config consistency checks, notification-resource validation, and release-file consistency checks.

Before publishing, run on a machine with Flutter 3.44.7+ stable and Android SDK 36:

```bash
flutter clean
flutter pub get
flutter analyze
flutter test
flutter run
bash scripts/release_check.sh
```

Test budget-notification permission, Android launcher quick actions, receipt OCR, category budgets, goals, calendar mode, income flows, and the SQLite v1→v2 migration on real Android devices before production.
