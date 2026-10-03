# Privacy Policy — Budget Tracker

**Effective date:** October 2, 2026

Budget Tracker is designed as a local-first personal finance utility. This policy explains how the app handles information.

## Information you enter

Budget Tracker can store information you choose to enter, including income and expense descriptions, amounts, categories, dates, notes, monthly and category budgets, savings goals, currency display preference, and app settings. This information is stored locally on your device to provide the app's features.

## Receipt scanning

If you choose to scan a receipt, you can take a photo or select an image from your device. Text recognition is performed on-device using Google ML Kit. The app can use recognized text to suggest a merchant, total amount, date, currency, VAT/tax amount, receipt number, and category. Budget Tracker does not intentionally upload your receipt image or recognized receipt text to an app-operated server.

## Budget alerts

Budget alerts are optional and disabled by default. If you enable them, the app may request Android notification permission and can create local device notifications when spending reaches configured thresholds or exceeds a category budget. These alerts do not require Budget Tracker to send your financial data to a server.

## Home-screen shortcuts

The app can expose local Android launcher shortcuts for adding an expense, adding income, and scanning a receipt. Using these shortcuts does not transmit financial data to an app-operated server.

## Google Drive backup

Google Drive backup is optional and disabled until you connect a Google account. If enabled, Budget Tracker can upload backup snapshots containing your transactions, goals, categories, budgets, currency preference, theme preference, budget-cycle start day, and budget-alert setting to the app's private Google Drive application-data area. The app requests the narrow Google Drive app-data permission and does not need access to your normal Drive files.

Automatic backup can be set to Off, Daily, Weekly, or Monthly. Automatic backups run while the app is active and only when local data has changed. You can also start a backup manually or restore the latest available backup from Settings.

## Shared budgets

Creating a shared budget uploads a copy of its transactions, categories, budgets, savings goals and recurring rules to a visible Google Sheet in the connected account's Drive. Joining an existing shared budget downloads that Sheet's data into a separate local workspace. Each participant authenticates with their own Google account. Only people with Google sharing access can access the Sheet; editor invitations grant editing permission and Google sends an invitation email.

Sync sends additions, edits and deletion records directly to Google Sheets. Change history includes the editor's Google email and retains prior versions, including deleted entries. Offline edits are cached locally and uploaded when syncing succeeds. Theme, notification preferences and backup schedules remain local. The app requests Google Sheets permission to open invited Sheets by URL, plus per-file Drive access for creating and sharing app-created Sheets. It only operates on the Sheet explicitly selected in the app.

The owner can revoke access using Google sharing settings or delete the spreadsheet. Revoking access prevents future sync; it does not erase data that another participant already downloaded, exported or backed up. Shared deletion records do not erase historical rows. To remove the complete shared history, the owner must delete the Sheet in Drive and participants must remove their local app data and any exports/backups separately.

## Internet, accounts, analytics, and advertising

The production Android manifest requests Internet access for optional Google Drive backups and shared Google Sheets budgets. Google sign-in is used when you explicitly connect either feature. Budget Tracker does not include advertising or analytics SDKs and does not send budgeting data to an app-operated server.

## Data sharing

Budget Tracker does not sell your personal information. The app does not send your budgeting data to an app-operated server or share it with advertisers. If you enable Google Drive backup, backup data is sent directly from the app to Google Drive under your Google account.

## Data retention and deletion

Your saved financial data remains on your device until you remove it. You can delete individual transactions and goals in the app or use **Settings → Clear local data** to remove transactions and goals and reset budgets, categories, currency preference, and budget-alert settings. Uninstalling the app also removes its locally stored app data, subject to device and operating-system behavior.

## Children

Budget Tracker is a general-purpose budgeting utility and is not designed to collect personal information from children.

## Changes to this policy

If the app's data practices change, this privacy policy should be updated before a release containing those changes is published.

## Contact

Before publishing this policy, replace this section with a real support email address that users can contact with privacy questions.

**Support email:** `REPLACE_WITH_YOUR_SUPPORT_EMAIL`

Shared budgets also store an optional display name alongside the editor email in new change-history entries. These names are visible to other editors and remain in previous revisions when the name changes.

Budget details reads and caches the selected Sheet owners and access grants that Google permits the signed-in account to view, including names, emails, group/domain/link access and roles. The app does not expand group membership or read sharing information for unrelated Drive files.
