# Budget Tracker

A production-oriented Flutter budget tracker for Android with income and expense tracking, receipt OCR, savings goals, monthly reports, custom categories, optional local budget alerts, calendar activity, and local-first storage.

## Product highlights

- Income and expense tracking with separate categories
- Recurring income and expenses for salary, allowance, rent, subscriptions and other regular payments
- Built-in income categories for Salary, Freelance, Refunds, Gifts, and Other Income
- Custom budget cycles: choose day 1–31 so your money month can follow your salary date
- Budget-cycle dashboard with spent/remaining progress
- Optional category budgets for expense categories
- Optional local budget notifications at 50%, 80%, and 100% of the monthly budget, plus exceeded category limits
- Savings goals with visual progress and add/withdraw controls
- Budget-cycle reports with income, spending, net savings, savings rate, comparisons, category charts, and budget status
- Calendar view for daily activity
- Custom categories with editable names, icons, and expense-category budgets
- Currency display settings: EGP, USD, EUR, SAR, AED, GBP, and KWD
- Camera/gallery receipt scanning with on-device Google ML Kit OCR
- Improved receipt parsing for merchant, total, date, currency, VAT/tax, receipt number, and category suggestions
- Native Android home-screen shortcuts: Add expense, Add income, Scan receipt
- Search, type/category filters, edit, swipe delete, and Undo delete
- SQLite transaction persistence plus local preference storage for goals/settings/categories
- System, light, and dark themes
- Optional Google Drive backups using the private app-data scope; Off/Daily/Weekly/Monthly schedules plus manual backup/restore
- No ad SDK or analytics SDK
- Android target/compile SDK 36

## Recommended toolchain

Use Flutter **3.44.7 or newer stable** and Android SDK Platform 36.

```bash
flutter pub get
flutter analyze
flutter test
flutter run
```

This project sets `kotlin.incremental=false` to avoid the Windows cross-drive Kotlin cache failure (`this and base files have different roots`) you hit when the project and Pub cache are on different drives. Builds may be a little slower; if you later keep both on the same drive and confirm stable builds, you can remove that line from `android/gradle.properties`.

## Android release setup

1. Install Android SDK Platform 36.
2. Create an upload keystore:

```bash
bash scripts/create_upload_key.sh
```

3. Copy `android/key.properties.example` to `android/key.properties` and enter your private signing values.
4. Build the Play Store bundle:

```bash
flutter build appbundle --release
```

The bundle will be at `build/app/outputs/bundle/release/app-release.aab`.

> The fallback release configuration is debug-signed when `android/key.properties` is missing so local release testing remains possible. Do not upload that fallback build to Google Play.

## Package ID

`com.smartbudget.tracker`

Verify this before your first Play Store upload. The application ID cannot be changed for an existing Play listing.

## Google Drive backup setup

Drive backup uses the narrow `drive.appdata` OAuth scope so Budget Tracker cannot browse the user's normal Drive files.

1. Create or select a Google Cloud project.
2. Enable **Google Drive API**.
3. Configure the OAuth consent screen.
4. Register an Android OAuth client for package `com.smartbudget.tracker` with the SHA-1 fingerprints for the signing keys you use.
5. Create a Web OAuth client ID and use that value as the server client ID.
6. Build/run with:

```bash
flutter run --dart-define=GOOGLE_SERVER_CLIENT_ID=YOUR_WEB_CLIENT_ID.apps.googleusercontent.com
```

The repository defaults to the Budget Tracker Web OAuth client supplied by the project owner, so regular builds include Google sign-in configuration. Other deployments should use their own `--dart-define` for both debug and release builds. Pass an empty `GOOGLE_SERVER_CLIENT_ID` to disable Drive integration.

The locally distributed update APKs use Android package `com.smartbudget.tracker` and signing-certificate SHA-1 `0C:64:4E:36:5C:36:E0:1F:9C:55:62:A9:6C:8E:7B:3F:1B:FA:C9:4F`. Register that exact pair as an Android OAuth client in the same project as the Web client. CI's temporary debug signing key is different; its unsigned-for-distribution artifacts must be signed with the registered key before Google sign-in can work. In OAuth testing mode, every person connecting must be listed as a test user. The client ID is a public identifier; do not embed or commit a client secret or private signing key.

## Shared Google Sheets budgets

Enable **Google Sheets API** in the same Cloud project as Drive. Shared budgets additionally request `spreadsheets` access to join a Sheet by URL, and `drive.file` access to create and share app-created Sheets. The app reads and writes only the Sheet explicitly selected by the user. While OAuth is in Testing, add each participant's Google email under Google Auth Platform → Audience → Test users. Wider public distribution of the sensitive Sheets scope requires the appropriate Google OAuth publishing/verification process.

1. Install the same update on each phone. Each person uses their own Google account.
2. Settings → Shared budget → Create shared budget copies the current personal budget into a new visible Google Sheet. The original personal budget is kept in its existing local database/preferences. Shared budgets have separate local databases/preferences.
3. Invite editor grants the specified Google account editing access and sends Google's invitation email. Copy Sheet link and give it to the invited person. Sharing can also be managed in Google Sheets.
4. The other person selects Settings → Shared budget → Join shared budget and pastes that link.
5. Activity, Reports, budgets, categories, goals, recurring rules and imports/exports now use the selected shared budget. Switching to personal budget restores the original personal data. Sync pending edits before switching.

Sync runs after local edits, every 30 seconds while the app is open, and on resume. Offline edits remain in a persisted outbox. Upload retries acknowledge existing change IDs before appending again. Separate entities merge independently. Concurrent versions of the same item are retained and shown under Shared budget → Conflicting edits; select the version to keep. Recurring occurrences retain deterministic IDs so two phones do not count the same occurrence twice. Theme, alerts and backup schedules remain local preferences.

The spreadsheet's **Changes** tab is an append-only revision history, not a flat Excel export. App edits add rows instead of overwriting the entire file. For direct spreadsheet edits, follow its **Read me** tab: modify the human-readable transaction fields on the latest revision, or set Deleted to TRUE. Do not remove history rows or edit Change ID, Item or Replaces. Invalid rows or removed history pause sync with an actionable error; existing local data and pending edits are kept. Direct edits to an old revision can correctly produce a conflict. Use the app's CSV/Excel export for a flat current transaction report.

Private Drive backups still work. Restore is restricted to personal mode so restoring an old snapshot cannot accidentally replace a live shared budget. Clearing data while a shared budget is selected explicitly warns that deletions affect everyone.

Automatic backup defaults to **Daily (recommended)** after the user connects. It only uploads when local data changed and the app is active, so it avoids unnecessary Drive writes. It retains the newest 10 snapshots. Users can choose Off, Daily, Weekly, or Monthly and can manually back up or restore the latest snapshot.

## Recurring transactions

Settings → **Recurring transactions** can automate regular income and expenses.

- Create monthly salary/allowance entries on any day from 1–31.
- Create weekly recurring income or expenses on a selected weekday.
- Monthly dates 29–31 automatically fall back to the final valid day in shorter months.
- Optional start and end dates.
- Pause/resume and edit future payments without deleting already-created Activity entries.
- Missed due dates are caught up when the app next opens or resumes.
- Each occurrence uses a deterministic rule/date ID plus a saved last-generated date, preventing duplicate automatic entries.
- Monthly recurring income can optionally set the same day as the app's budget-cycle start.
- Recurring rules are included in private Google Drive backup snapshots. Generated occurrences are normal transactions, so they also appear in Activity, Overview, Reports, Excel and CSV exports.

## Salary / budget cycles

Budget cycles can start on any day from 1 to 31. If salary arrives on the 25th, set **Settings → Budget cycle → Day 25**; a cycle such as September 25–October 24 is then used consistently for the dashboard, budget limits, alerts, statistics, comparisons, and category budgets. For start days 29–31, shorter months automatically use that month's final valid day.

## Importing from Money Tracker / other apps

Settings → **Import data → Import CSV or Excel** opens a migration wizard for transaction history.

The importer is specifically compatible with the documented export/import conventions of **Money Tracker by Paraga Mobile** (`io.paraga.moneytracker`):

- CSV and XLSX files
- `Date`, `Category`, and `Remark`/description columns
- one signed `Amount` / `Amount(Auto)` column (positive income, negative expense)
- or split `Amount(Income)` / `Amount(Expense)` columns
- Money Tracker's documented numeric and month-name date formats
- Wallet, currency, and label metadata are preserved in the imported transaction note when those columns exist
- transfer rows are skipped because Budget Tracker currently models income/expense, not wallet-to-wallet transfers
- duplicate rows are detected before import
- unknown categories are created automatically
- the user sees a preview and can correct column mapping before anything is saved

If a Money Tracker export contains multiple currencies, Budget Tracker warns before import. Amounts are not exchange-rate converted; source wallet/currency metadata is preserved in the note.

## Excel and CSV export

Settings → **Export data** provides two human-readable exports:

- **Excel (.xlsx):** includes a Transactions sheet plus a Summary sheet with total income, expenses, net, currency, transaction count, and budget-cycle start day.
- **CSV:** includes all transactions in a format that opens in Excel, Google Sheets, and other spreadsheet apps.

Both formats include the budget-cycle range that each transaction belongs to. Android's share/save sheet is used, so the file can be saved locally, sent to another app, or placed in Drive.

These exports are **not** app restore files. Google Drive backup uses the private JSON snapshot format because it preserves the app's complete data/settings for reliable restoration.

## Privacy

The release app requests Internet access for the optional Google Drive backup feature. Financial entries remain local unless the user explicitly connects Google Drive. Receipt OCR is still performed on-device. Optional budget alerts use local Android notifications and request notification permission only after the user enables the feature.

Currency switching is display-only: changing from EGP to USD/EUR/etc. does not convert existing numeric amounts using exchange rates.

## Play Store materials

See `PLAY_STORE_RELEASE_CHECKLIST.md`, `PRIVACY_POLICY.md`, `store_assets/STORE_LISTING.md`, and `store_assets/DATA_SAFETY_NOTES.md`.

Shared transaction cards show Added by and Last edited by from the shared change history. Each participant can set Your display name in Shared budget; future revisions include the name and Google email. Earlier revisions keep their recorded author. Direct Sheet edits use the Editor cell, so these labels are attribution rather than a verified audit trail.
