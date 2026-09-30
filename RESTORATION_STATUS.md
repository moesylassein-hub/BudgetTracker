# Budget Tracker restoration status

## Verified inputs

- Compiled Android APK is being treated as the behavioral source of truth.
- A surviving Flutter `app.dill` debug artifact was recovered from the uploaded project archive.
- The `app.dill` contains embedded source text for all 25 project Dart files.
- Those 25 recovered Dart files match the uploaded older-source ZIP byte-for-byte.
- APK AOT symbol inspection maps the same app-specific private classes and methods to those 25 files; no additional app Dart file paths were found.

## Recovered Dart files

- `lib/main.dart`
- `lib/controllers/app_controller.dart`
- Models: budget category, receipt scan result, savings goal, transaction
- Screens: add transaction, categories, dashboard, home shell, savings goals, scan receipt, settings, statistics, transactions
- Services: local storage, notifications, OCR, receipt parser
- Theme, currency/category/formatter utilities
- Budget and transaction widgets

## APK features already identified

- Expense and income transactions
- Monthly budgets and category budgets
- Budget alerts at 50%, 80%, 100%, and category-limit alerts
- Savings goals and savings adjustments
- Monthly reporting/statistics
- Calendar activity view
- Search/filtering and transaction edit/delete/undo
- Receipt scanning with on-device Google ML Kit OCR
- Receipt parsing for merchant, total, date, currency, tax, receipt number, and category
- Camera/gallery receipt input
- Custom expense/income categories and icons
- Currency selection
- System/light/dark themes
- Android quick actions for adding expense/income and scanning receipts
- SQLite migration preserving older transactions
- Local-first privacy/data-clear flow

## Important

Matching filenames and method names do not prove the older source is behaviorally identical to the APK. UI/layout values, branches inside methods, validation, copy, defaults, and smaller interactions can differ without introducing new method names. The APK therefore remains the reference for reconstruction and verification.
