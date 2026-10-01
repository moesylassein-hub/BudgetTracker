# Budget Tracker

A production-oriented Flutter budget tracker for Android with income and expense tracking, receipt OCR, savings goals, monthly reports, custom categories, optional local budget alerts, calendar activity, and local-first storage.

## Product highlights

- Income and expense tracking with separate categories
- Built-in income categories for Salary, Freelance, Refunds, Gifts, and Other Income
- Custom budget cycles: choose day 1–28 so your money month can follow your salary date
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

Use the same `--dart-define` for release builds. Without it the rest of the app works normally, but Settings shows Drive backup as not configured.

Automatic backup defaults to **Daily (recommended)** after the user connects. It only uploads when local data changed and the app is active, so it avoids unnecessary Drive writes. It retains the newest 10 snapshots. Users can choose Off, Daily, Weekly, or Monthly and can manually back up or restore the latest snapshot.

## Salary / budget cycles

Budget cycles can start on any day from 1 to 31. If salary arrives on the 25th, set **Settings → Budget cycle → Day 25**; a cycle such as September 25–October 24 is then used consistently for the dashboard, budget limits, alerts, statistics, comparisons, and category budgets. For start days 29–31, shorter months automatically use that month's final valid day.

## Privacy

The release app requests Internet access for the optional Google Drive backup feature. Financial entries remain local unless the user explicitly connects Google Drive. Receipt OCR is still performed on-device. Optional budget alerts use local Android notifications and request notification permission only after the user enables the feature.

Currency switching is display-only: changing from EGP to USD/EUR/etc. does not convert existing numeric amounts using exchange rates.

## Play Store materials

See `PLAY_STORE_RELEASE_CHECKLIST.md`, `PRIVACY_POLICY.md`, `store_assets/STORE_LISTING.md`, and `store_assets/DATA_SAFETY_NOTES.md`.
