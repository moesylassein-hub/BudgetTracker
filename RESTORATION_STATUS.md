# Budget Tracker restoration status

## Status

**Restoration complete and build-verified.**

The compiled Android APK was treated as the behavioral source of truth, with the surviving Flutter source/build artifacts used as the reconstruction base.

## Recovery evidence

- A surviving Flutter `app.dill` debug artifact exposed source text for all 25 project Dart files.
- Those recovered Dart files matched the uploaded source archive byte-for-byte where expected.
- APK AOT inspection referenced the same app-specific Dart file set; no additional app Dart source paths were found.
- APK manifest inspection confirmed package `com.smartbudget.tracker`, app label `Budget Tracker`, and version name `1.0.0`.
- The repository keeps version `1.0.0+1` to match the recovered APK rather than the source archive's later 1.1.0 label.

## Reconstructed app coverage

- Expense and income transactions
- Add, edit, delete, and undo transaction flows
- Search and category/type filtering
- Monthly budgets and category budgets
- Budget alerts at 50%, 80%, 100%, plus category-limit alerts
- Savings goals and savings adjustments
- Statistics and monthly reporting
- Calendar activity view
- Receipt scanning with on-device Google ML Kit OCR
- Camera and gallery receipt input
- Receipt parsing for merchant, total, date, currency, tax, receipt number, and category
- Custom expense/income categories and icons
- Currency selection
- System, light, and dark themes
- Android quick actions for adding expense/income and scanning receipts
- SQLite storage and legacy transaction migration
- Local-first privacy information and clear-local-data flow

## Android/project reconstruction

The repo includes the normal Flutter/Android project structure, Gradle configuration, Android manifests/resources, tests, release helper scripts, and CI verification. A duplicate Kotlin activity recovered from the archive was intentionally not kept because the Android project already uses the Java `MainActivity`; keeping both causes a duplicate-class build failure.

## Build verification

GitHub Actions successfully completed all of the following on the reconstructed project:

1. `flutter pub get`
2. `flutter analyze`
3. `flutter test`
4. `flutter build apk --debug`

The successful verification run was produced after the APK version was aligned and the duplicate Android activity was removed.

## Remaining limitation

A compiled APK cannot prove original comments, formatting, local variable names, or every source-level implementation detail. The restored repository therefore aims to reproduce the APK's observable features and behavior while preserving exact recovered source wherever it survived.
