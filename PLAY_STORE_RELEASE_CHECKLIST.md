# Google Play Release Checklist

## Code and build

- [x] Android platform project included
- [x] `targetSdk = 36`
- [x] `compileSdk = 36`
- [x] Minimum Android SDK 24
- [x] Release code shrinking enabled
- [x] Cleartext network traffic disabled
- [x] No Internet permission in release manifest
- [x] Adaptive launcher icon resources included
- [x] Android 12+ splash styling included
- [x] Release version updated to `1.1.0+2`
- [x] Kotlin incremental compilation disabled to avoid the Windows C:/E: Pub-cache path failure seen during testing
- [ ] Install a current stable Flutter SDK compatible with this project and Android SDK 36 on your build machine
- [ ] Run `flutter pub get`
- [ ] Run `flutter analyze`
- [ ] Run `flutter test`
- [ ] Test camera/gallery receipt scanning on at least one real Android device
- [ ] Test light mode, dark mode, large text, and small-screen layout
- [ ] Confirm OCR results on several real receipts and currencies you intend to support

## Version 1.1 feature QA

- [ ] Add expense transactions and confirm totals decrease correctly
- [ ] Add income transactions (salary, freelance, refund, gift) and confirm income/net totals
- [ ] Edit both expense and income transactions
- [ ] Delete a transaction and test **UNDO**
- [ ] Create, edit and delete an unused custom category
- [ ] Verify a category in use cannot be deleted accidentally
- [ ] Choose category icons and verify them in transaction/activity views
- [ ] Set category monthly budgets and verify progress/status
- [ ] Enable budget alerts and grant notification permission
- [ ] Confirm overall alerts at 50%, 80% and 100% only fire once per threshold/month
- [ ] Confirm category alert fires only after exceeding its category limit and does not spam repeatedly
- [ ] Disable budget alerts and verify no further local budget notifications are shown
- [ ] Create/edit/delete savings goals and test add/withdraw progress updates
- [ ] Browse previous months in Monthly Reports and compare month-over-month values
- [ ] Change currency between EGP/USD/EUR/SAR/AED/GBP/KWD and verify formatting throughout the app
- [ ] Confirm changing currency does **not** convert historical numeric amounts (display currency only)
- [ ] Test Activity list search/type/category filters
- [ ] Test Activity calendar mode and selected-day totals
- [ ] Long-press the Android launcher icon after launching once and test Add expense / Add income / Scan receipt shortcuts
- [ ] Test improved OCR extraction for merchant, total, date, VAT/tax, receipt number, and detected currency
- [ ] Test a receipt whose detected currency differs from the selected app currency and verify the warning is clear
- [ ] Test the Settings > Monthly budget dialog: Save and Cancel must both close without a red-screen assertion

## Signing

- [ ] Create your private upload keystore with `scripts/create_upload_key.sh`
- [ ] Create `android/key.properties` from `android/key.properties.example`
- [ ] Back up the upload key and passwords securely
- [ ] Build a release AAB: `flutter build appbundle --release`
- [ ] Never upload a debug-signed fallback build

## Google Play Console

- [ ] Verify the application ID `com.smartbudget.tracker` before the first upload
- [ ] Create the app in Play Console
- [ ] Enroll in Play App Signing
- [ ] Upload `app-release.aab`
- [ ] Complete the app content questionnaire
- [ ] Complete the Data safety form using `store_assets/DATA_SAFETY_NOTES.md` as a starting point
- [ ] Set app category (recommended: Finance)
- [ ] Add support email
- [ ] Host `PRIVACY_POLICY.md` at a public HTTPS URL and add it to Play Console
- [ ] Review whether your store listing needs a financial-features declaration under current Play policies
- [ ] Complete content rating
- [ ] Complete target audience and ads declarations
- [ ] Add app access instructions (normally “all functionality available without login”)
- [ ] Review the notification-permission disclosure and ensure alerts are clearly optional

## Store listing assets

- [x] Draft title, short description, and full description included
- [x] 512×512 store icon included
- [x] 1024×500 feature graphic included
- [ ] Capture real Android phone screenshots from the final build
- [ ] Include screenshots of Overview, income/expense entry, Monthly Reports, Goals, calendar, and receipt scan
- [ ] Review screenshots for private or test data
- [ ] Add optional tablet screenshots if you intend to support/market tablet layouts

## Final QA before production

- [ ] Install the Play internal-testing build from Google Play, not just a local APK
- [ ] Restart the app and confirm transactions, categories, goals, currency, budget and alert settings persist
- [ ] Scan receipt from camera
- [ ] Scan receipt from gallery
- [ ] Test receipt with no clear total and confirm graceful fallback
- [ ] Verify the app launches offline
- [ ] Verify Android notification permission is not requested unless Budget alerts are enabled
- [ ] Confirm no crashes in Play pre-launch report
- [ ] Increment version code for every future upload
