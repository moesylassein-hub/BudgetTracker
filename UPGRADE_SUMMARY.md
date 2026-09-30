# Upgrade summary — Version 1.1

This feature pass expands Budget Tracker from expense-only tracking into a fuller personal-finance app while keeping the local-first design.

## Added in 1.1

- Income tracking with Salary, Freelance, Refunds, Gifts, and custom income categories
- Savings goals with visual progress and savings adjustments
- Optional budget alerts at 50%, 80%, and 100% plus category-budget exceed alerts
- Per-category monthly budgets for expense categories
- Monthly reports with income, spending, net savings, savings rate, previous-month comparisons, and category charts
- Currency display settings for EGP, USD, EUR, SAR, AED, GBP, and KWD
- Custom categories with editable icons and category limits
- Improved receipt parsing for total, currency, VAT/tax, receipt number, date, merchant, and category
- Native Android launcher shortcuts for Add expense, Add income, and Scan receipt
- Undo delete
- Calendar activity view with daily income/spending summaries
- Database migration that preserves existing 1.0 transactions as expenses
- Updated Google ML Kit text recognition dependency compatible with the newer Android Kotlin migration path
- Safer app rebuild architecture so transaction/category updates no longer rebuild the entire `MaterialApp`
- Budget editor Cancel/Save flow keeps the no-controller dialog fix that avoids the `_dependents.isEmpty` assertion
- Windows cross-drive Kotlin cache workaround enabled in `android/gradle.properties`

## Existing production work retained

- SQLite local transaction persistence
- Material 3 light/dark themes
- API 36 Android configuration
- Release shrinking/signing setup
- On-device OCR
- Privacy policy, Data Safety notes, Play listing materials, and release checklist
