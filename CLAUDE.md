# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

KashU is a privacy-focused, offline-first Flutter app for tracking an investment portfolio (stocks, mutual funds, metals, crypto, deposits, real estate, cash). All portfolio data lives locally in encrypted Hive boxes; the network is only used to fetch price/forex data.

`docs/TECHNICAL_DECISIONS.md` records the *why* behind the Flutter / Riverpod / Hive choices, the data-model shape, and the Phase-1 security posture — read it before relitigating those decisions. Its *UI/UX Decisions* section is stale, though: the app is no longer dark-first (both themes built; System/Light/Dark setting) and no longer system-font-only (Quicksand / Plus Jakarta Sans, bundled in `assets/fonts/`) — the "C·Soft" section below supersedes it.

## Commands

```bash
flutter pub get                                          # install deps
dart run build_runner build --delete-conflicting-outputs # regenerate *.g.dart (after any model change, see below)
flutter analyze --fatal-infos                            # lint + type check (CI gate)
flutter test                                             # run all tests
flutter test test/services/gold_price_service_test.dart  # run a single test file
flutter test --name "applies Indian taxes"               # run tests matching a name
```

**Rerun code generation after any model change.** The four Hive adapters (`lib/data/models/*.g.dart`) are generated from `@HiveType`/`@HiveField` annotations and **are committed** — `.gitignore` deliberately leaves them un-ignored — so a model edit must ship with its regenerated adapter, or the build breaks with missing-symbol errors. CI reruns `build_runner` before `flutter analyze` regardless, which means CI won't catch a stale committed adapter. Riverpod codegen is not in use: `riverpod_generator` is a dev dependency, but there are no `@riverpod` annotations and every provider is hand-written.

CI (`.github/workflows/ci.yml`) runs on push to `main`/`staging`/`p0-improvements` and PRs to `main`/`staging`. Two jobs:
1. `analyze-and-test` — pub get → build_runner → `flutter analyze --fatal-infos` → `flutter test --coverage`. `--fatal-infos` means even lint infos fail the build.
2. `build-android` — runs only if the first passes; Java 17 + `flutter build apk --release` (debug-signed until a release keystore is wired in from secrets).

CI pins **Flutter 3.44.1 (stable)**, the same version release builds use — match it locally to avoid analyzer drift.

Two other workflows live alongside it and never gate a merge: `claude.yml` (responds to `@claude` on issues/PR comments) and `claude-code-review.yml` (auto-reviews opened PRs). `ci.yml` is the only required check.

### Repo automation (`.claude/`)

Two hooks in `.claude/settings.json` enforce the rules above mechanically, so they usually don't need running by hand:
- **PostToolUse** (`regen-on-model-change.sh`) — reruns `build_runner` after any edit to a hand-written file in `lib/data/models/`.
- **Stop** (`analyze-on-stop.sh`) — runs `flutter analyze --fatal-infos` before a turn ends, but only when there are uncommitted `.dart` changes.

Project slash commands live in `.claude/commands/` (`/regen`, `/hive-migration`, `/add-asset-type`, `/triage`, `/fix-web-bug`, `/commit`, `/pr`) and encode the canonical multi-step flows.

### Running on each platform

- **Web**: requires a CORS proxy — browsers block direct calls to Yahoo Finance / CoinGecko / MFAPI.in / open.er-api.com. Locally: `flutter build web`, then `python3 proxy_server.py`, which serves `build/web` and proxies at `http://localhost:8080`. Deployed: Vercel (see below). Both expose the **same** contract, `/api/proxy?url=<encoded absolute https URL>` (`proxy_server.py` also still answers the legacy `/proxy?` path).
- **Android**: `flutter build apk --debug` on macOS/Linux. On Windows use `build_apk.bat` (the Android build tools are Windows `.exe` and cannot run from WSL2). `MainActivity` must stay a `FlutterFragmentActivity` and the launch/normal themes must keep an AppCompat parent: `local_auth`'s BiometricPrompt needs both, and with a plain `FlutterActivity` every unlock fails with `no_fragment_activity`.
- **iOS/macOS**: `flutter build ios --debug` / standard Flutter. Podfiles for ios/macos may be untracked locally.

### Web deployment (Vercel)

Production is <https://kash-u.vercel.app>. `vercel.json` publishes the prebuilt `build/web` as static output (`buildCommand` is empty — build locally and deploy; git auto-deploys are disabled) and rewrites everything except `/api/*` to `index.html`. `flutter_bootstrap.js`, `flutter_service_worker.js`, `version.json`, and `index.html` are served `no-cache` so clients don't pin a stale build.

`api/proxy.py` is the serverless twin of `proxy_server.py` (Python stdlib only, no `requirements.txt`). It is not a general relay: a per-host **path-prefix allowlist** (`ALLOWED_HOSTS`) gates every request, each redirect hop is re-validated against that allowlist so an open redirect on an allowed host can't escape it, bodies over ~10MB are refused, and responses are edge-cached per upstream host and gzipped (MFAPI's full scheme list is ~5.7MB). Adding a new upstream API means adding its host **and** path prefixes to *both* proxies.

**Deploying is manual** — there is no CI deploy job, and `git.deploymentEnabled: false` means pushing to GitHub never ships anything. From a machine that can build the web bundle:

```bash
dart run build_runner build --delete-conflicting-outputs
rm -rf build/web && flutter build web --release   # not `flutter clean` — that also wipes the multi-GB ios/macos builds
vercel             # preview deploy; verify against this URL first
vercel --prod      # promote
```

**`.vercelignore` is load-bearing and is an allowlist, not a denylist**: the Vercel CLI uploads the entire working tree and ignores `.gitignore`, so without it a deploy would try to push the ~4GB `build/` tree (`build/ios` alone is 2.6GB) instead of the ~42MB `build/web`. Any new root-level path Vercel has to serve must be re-admitted there with `!`. The function needs no env vars or secrets.

### Crash reporting (Sentry)

Sentry is a no-op unless a DSN is provided at build time:
```bash
flutter build apk --dart-define=SENTRY_DSN=https://xxx@sentry.io/yyy --dart-define=APP_ENV=production
```
`AppConfig` (`lib/core/config/app_config.dart`) reads these via `String.fromEnvironment`.

A DSN alone is not enough: crash reporting is **strictly opt-in**, so `main()` requires `AppConfig.isSentryEnabled` **and** the runtime consent flag (`AppConstants.keyCrashReportingEnabled`, read through `crashReportingConsentGiven` — only a literal `true` counts; a missing key or a corrupted value means no). That is why `_preBootstrap` opens the settings box *before* `SentryFlutter.init`, and why `beforeSend` re-reads the flag so switching the toggle off mid-session takes effect immediately.

## Architecture

Layered structure under `lib/`:
- `core/` — config, constants, theme, and utils (Result type, retry helper, import validation, platform/currency formatting). No app logic.
- `data/` — Hive `models/` (+ generated adapters), `repositories/` (Hive access), and `migration/` (schema versioning).
- `services/` — all network/price/business logic. Stateless services, instantiated via Riverpod providers.
- `features/` — one folder per screen/flow (dashboard, assets, transactions, rebalancing, export, settings, auth, onboarding).
- `shared/` — `providers/` (Riverpod) and reusable `widgets/` (the asset search fields, charts).

### State management — Riverpod

`lib/shared/providers/portfolio_provider.dart` is the wiring hub: it constructs repositories and services and exposes them as providers, plus derived state like `portfolioSummaryProvider` (FutureProvider), `baseCurrencyProvider`, and price-refresh status providers. Services take their dependencies via constructor (with defaults) so they're testable — providers inject the shared singletons. When adding a service, follow this pattern: constructor-injected deps + a `Provider` in this file.

**Providers do not observe Hive.** Nothing uses `box.listenable()`; `allAssetsProvider` is a one-off read of the repository, cached until it is invalidated. Any screen that writes assets or transactions must call `ref.invalidate(allAssetsProvider)` and `ref.invalidate(portfolioSummaryProvider)` afterwards (see the add/detail/settings screens), or the dashboard keeps showing the old numbers.

### Persistence — Hive (encrypted)

Five boxes, opened in two phases in `main.dart`: `settings_box` first, in `_preBootstrap()` (so the crash-reporting consent flag can be read before Sentry initialises), then `assets_box`, `transactions_box`, `price_cache_box` and `price_history_box` in `_bootstrap()` (names in `AppConstants`). All boxes are AES-encrypted with a 256-bit key generated once and stored in the platform keychain/keystore via `flutter_secure_storage` (`DatabaseKeyService`, `data/security/`). If the key can't be read, is missing while boxes exist, or fails the key check recorded in the unencrypted `key_check_box`, or a box fails to open (corruption/full disk), the app shows `DatabaseErrorApp` (`features/startup/`) — "Try again", or a confirmed reset that deletes the boxes and key — instead of crashing. **Never open a box with a key that hasn't passed that check**: Hive's crash recovery treats every frame encrypted with another key as corrupt and truncates the file, silently wiping the data.

**Android backup is switched off on purpose.** `AndroidManifest.xml` sets `allowBackup="false"` plus `fullBackupContent` / `dataExtractionRules` (`res/xml/`) excluding all app data from cloud backup and device-to-device transfer: the boxes and the secure-storage prefs would arrive on a new phone without the Keystore key that decrypts them. The JSON export/import is the supported way to move a portfolio.

**On web the storage story is weaker, and it is not guarded by `kIsWeb`.** `Hive.initFlutter()` has no web branch, so each box becomes its own **IndexedDB** database, and `flutter_secure_storage_web` keeps the AES key — plus the WebCrypto key that wraps it — in the same origin's `localStorage`. That is obfuscation at rest, not a keychain. Consequences worth knowing before touching web behaviour: clearing site data destroys the portfolio outright; iOS Safari evicts the storage of a site not visited for 7 days unless it was added to the Home Screen; and the app lock is inert (the Settings toggle is hidden and `AuthResult.notAvailable` simply unlocks). There is no server-side copy of anything, so an export is the only backup a web user has.

**Writing a file goes through `core/utils/file_saver.dart`.** It is a conditional export — `file_saver_io.dart` writes to the documents directory and opens the share sheet, `file_saver_web.dart` hands the bytes to the browser as a download. **Never import `dart:io` or `path_provider` outside `file_saver_io.dart`**: both compile on web and then throw at runtime (`getApplicationDocumentsDirectory()` has no web implementation, `File` writes raise `UnsupportedError` under dart2js), which is exactly how every web export silently failed into an `Export failed:` SnackBar before this split existed. `exportCapitalGainsPdf` is currently unreferenced — the tax screen calls `previewCapitalGainsPdf`, which goes to the browser/OS print dialog via `Printing.layoutPdf`.

`settings_box` doubles as the app's general key-value store, not just user preferences: the `AppConstants.key*` entries (base currency, theme mode, app lock, schema version, crash-reporting consent, backup nudge), the rebalancing targets under `rebal_{assetTypeName}` keys, and the `PortfolioWriteService` pending-write markers all live there.

**Schema migrations** (`data/migration/hive_migration_service.dart`): when you add/change a `@HiveField` on a model, bump `_currentSchemaVersion` and add a matching entry to the `_migrations` map. `runMigrations()` runs pending steps on startup after boxes open. Currently at version 1, whose only entry is the `_baseline` no-op — so the first real migration is `2:`. Model `typeId`s are fixed — `AssetType=0`, `TransactionType=1`, `Asset=2`, `Transaction=3` — never reuse or reorder field numbers. Those four are the only Hive types: `price_cache_box` and `price_history_box` store `jsonEncode`d strings (`CachedPriceEntry`, `DailySnapshot`), so they sit outside the typeId/migration system entirely, and their `fromJson` has to cope with entries written by older builds.

Repositories (`AssetRepository`, `TransactionRepository`) are the only place that touches Hive boxes directly. Derived portfolio math (`totalInvested`, `currentValue`, `gainLoss`) lives as getters on the `Asset` model, not in repositories.

**Cross-box writes go through `PortfolioWriteService`** (`data/repositories/portfolio_write_service.dart`), not the two repositories directly. Hive has no cross-box transactions, so a crash between the two halves of a combined write (add asset + log its BUY; delete asset + its transactions; Clear All Data) can leave the boxes inconsistent. This service compensates on failed adds and writes pending-write markers into the settings box for deletes, which `completeInterruptedWrites()` finishes on the next launch (`main.dart`). A backup import (`importBackup`) is all-or-nothing: it journals the previous value of every id it writes (`AppConstants.keyPendingImport`), rolls back on any failure, and a leftover journal is rolled back at startup. It only ever cleans up *marked* writes — orphaned transactions from any other source are real user history (they feed the Activity screen and tax exports) and must not be touched.

**Sales and income** (the Record-transaction sheet, `features/transactions/record_transaction_sheet.dart`) go through `PortfolioWriteService.recordSell` / `recordIncome`, validated by `core/utils/transaction_validator.dart` on both sides. A sell logs the SELL and lowers the asset's quantity in one compensated write; the average cost (`purchasePrice`) is unchanged. **A fully sold holding stays stored at quantity 0** — `ExportService.computeCapitalGains` looks the sell's cost basis and purchase date up on the asset, so deleting it would drop the gain from the tax report; screens treat quantity 0 as "sold" (no open gain, not counted as a holding). Deleting a SELL through `deleteTransaction` hands its units back.

### Price tracking — the core domain logic

`PriceService` (`services/price_service.dart`) is the abstract interface; `PriceSymbols` holds the per-`AssetType` routing rules (which types support auto-tracking, default symbols, input hints).

`PriceUpdateService` (`services/price_update_service.dart`) orchestrates a full refresh, routing each asset by `AssetType` into four separate batches:
- **crypto** → CoinGecko, then `CryptoCompareService` for whatever failed as **one batched call** (not per asset), then the cache — one such batch per holding currency, since a call quotes a single `vs_currency`. The app stores CoinGecko ids, so `CryptoCompareService._idToTicker` maps `bitcoin`→`BTC`; unmapped ids fail straight through to the cache. CryptoCompare reports errors as HTTP 200 with `{"Response": "Error"}`, so the body must be checked.
- **metals** (`AssetType.gold`) → `GoldPriceService`, split again by stored symbol (see below). There is no `AssetType.silver`: silver is a gold-type asset carrying `SI=F`, so this bucket makes one COMEX call per metal, not per asset.
- **mutual funds** → `MutualFundService` (MFAPI.in, keyed by AMFI scheme code — not Yahoo).
- **everything else** (stocks, bonds) → Yahoo Finance with **Stooq as fallback**.

Key behaviors to preserve when editing:
- Exchange rates are pre-fetched once per refresh and reused (`CurrencyConverterService`, backed by live USD→INR forex from `open.er-api.com`).
- Prices are converted into each asset's stored currency before saving, whatever the quote's currency (`QuoteCurrency` in `services/quote_currency.dart`; London quotes arrive in pence, `GBp`). A quote that cannot be converted with a live rate is treated as a failed fetch, never stored as is. The add-asset autofill follows the same rules: a quote in another supported currency moves the currency field to it unless the user picked one. The metal batch fetches once in `assets.first.currency` and re-derives the others from `breakdown.usdPerGram` — the COMEX leg is currency-agnostic, so a second currency costs no extra round trip.
- On API failure, it falls back to the last cached price (`PriceCacheService`, `price_cache_box`) before counting an asset as failed.
- Stock/bond refreshes are throttled (300ms between calls) to avoid rate limiting.

**Gold/silver pricing is computed, not fetched directly.** `GoldPriceService` fetches COMEX `GC=F`/`SI=F` (USD/troy oz) via Yahoo, converts oz→gram (÷31.1035) and USD→target currency via live forex, then applies Indian import duties + GST (`GoldTaxConfig.india` ≈ 9.18% for gold) only when the target currency is INR. This tax math is intentional and tested — see `test/services/gold_price_service_test.dart`.

**Silver rides on `AssetType.gold`, so every metal path must branch on the symbol.** `PriceSymbols.isComexSilver` / `metalSymbolFor` resolve the contract and `GoldTaxConfig.forMetal` the duty set (gold carries AIDC; silver pays a higher BCD). `_refreshMetalAssets` and `_refreshSingleMetal` both route through them — anything that reaches for `fetchGoldPriceBreakdown` directly will reprice silver at the gold rate, which is roughly 100× off.

**The metal price cache is keyed `SYMBOL:CURRENCY`** (`_metalCacheKey`), not by symbol alone. The cached number is a per-gram price in one currency, so a bare `GC=F` key lets an INR and a USD holding overwrite each other and hands one of them the other's number on the offline fallback.

**Never call `kIsWeb` from a service to pick a URL.** `PlatformConfig.buildUrl()` (`core/utils/platform_config.dart`) is the single place that decides between the direct URL (mobile/desktop) and the same-origin `/api/proxy?url=…` route (web), resolved against `Uri.base` so it works unchanged on localhost, Vercel previews, and production.

### Portfolio history and the home-screen widget

After each successful refresh the dashboard (`features/dashboard/dashboard_screen.dart`) fans out to two side effects:
- `PriceHistoryService.recordDailySnapshot()` writes one `DailySnapshot` per day into `price_history_box`, keyed `yyyy-MM-dd`, pruned to a 90-day `retention` window. `total` is in the base currency; `assetValues` are in each asset's **own** currency, because they only feed per-asset sparklines where the shape matters, not the unit. This also backs the day-over-day change (`previousDayTotal`).
- `WidgetUpdateService.updatePortfolioWidget()` writes formatted values to shared native storage and pokes the Android `AppWidgetProvider` / iOS WidgetKit app group. It returns early on web (`home_widget` has no web implementation and would throw `MissingPluginException`).

### Theming — "C·Soft"

`core/theme/app_theme.dart` builds both `lightTheme` and `darkTheme`; every screen is theme-aware. `MaterialApp.themeMode` watches `themeModeProvider` (`shared/providers/settings_providers.dart`), the Settings › Appearance choice — System (default), Light or Dark — persisted under `AppConstants.keyThemeMode`; it applies instantly and also themes onboarding and the lock overlay. **Don't hardcode colors, radii, shadows or fonts in widgets:**
- `AppColors` (`core/constants/app_colors.dart`) — the semantic tokens (`background`, `surface`, `textPrimary`, …) hold the **dark** values; their light counterparts live under `light*` tokens and are picked inside `AppTheme._build`. Per-`AssetType` colors (`stockColor`, `cryptoColor`, …) and the brand gradients live here too.
- `AppRadii` / `AppShadows` (`core/theme/app_decorations.dart`) — the shared corner radii and the soft purple-tinted shadows/glows.
- Typography is **Quicksand for headings, Plus Jakarta Sans for body/labels**, reached through the `TextTheme` or the `AppTheme.heading()` / `AppTheme.body()` helpers — never a `fontFamily` string in a widget. Both families are **bundled** (`assets/fonts/`, pubspec `fonts:`; there is no `google_fonts` dependency), so nothing is fetched at runtime. Only the weights in use ship — Quicksand 700, Plus Jakarta Sans 500/600/700/800 + 500 italic; Quicksand is its project's own static build, never one we cut ourselves, because its OFL reserves the name "Quicksand" and a modified font may not carry it; a new weight means extending `tool/build_fonts.py` and pubspec, and `test/core/theme/bundled_fonts_test.dart` checks they agree. The OFL texts are registered with `LicenseRegistry` (`core/theme/font_licenses.dart`).

### App startup flow

`main()` → `_startApp()` (re-run in-process by the recovery screen) → `_preBootstrap()`: error handlers → Hive init + register adapters → load and verify the key (`DatabaseKeyService`) → open `settings_box` (or the recovery screen). `_startApp()` then reads the crash-reporting consent flag and runs `_bootstrap()` either directly or as Sentry's `appRunner`. `_bootstrap(cipher)`: open the four data boxes → run migrations → finish interrupted cross-box writes (and roll back an interrupted import) → read settings flags → `runApp`. A failure in any of the first three lands on `DatabaseErrorApp` rather than a blank screen. `KashUApp` chooses the home screen by priority: onboarding > lock screen (biometric/PIN auth) > dashboard.

## Release packaging

- **Play requires an `.aab`**: `flutter build appbundle --release`. `android/app/build.gradle.kts`
  **throws at configuration time** if `android/key.properties` is absent, because an unsigned bundle
  is only ever destined for an upload that would be rejected. A release *APK* still builds with the
  debug key (CI smoke-builds one) but logs a loud warning — never ship that artifact.
- Store graphics come from `tool/generate_store_assets.py`, which imports the gradient and coin from
  `tool/generate_app_icon.py`, so the listing cannot drift from the shipped icon. Output lands in
  `store/play/` and is not bundled into the app.
- The privacy policy is a plain static page at `web/privacy.html`; `flutter build web` copies it into
  `build/web/`, and Vercel's filesystem phase serves it before the SPA rewrite, so `/privacy.html`
  works without touching `vercel.json`.
- **Lock files are tracked** (`pubspec.lock`, `ios/Podfile.lock`, `macos/Podfile.lock`). `.gitignore`
  has a blanket `*.lock` for Hive's box locks with explicit `!` exceptions — don't drop them, or
  release builds stop being reproducible and CI silently re-resolves dependencies every run.

## Conventions

- Tests use `mocktail` and live under `test/`, mirroring the `lib/` layout. Service tests inject fake HTTP clients / dependencies via the constructor params; Hive-backed services take a `Box?` override for the same reason, and the test opens that box against a `Directory.systemTemp.createTemp()` path (`Hive.init(tempDir.path)`), tearing it down with `Hive.deleteFromDisk()`.
- **Two version numbers look alike — don't cross them.** `AppConstants.backupFormatVersion` (currently 2) versions the export/import JSON and is enforced by `ImportValidator`; `_currentSchemaVersion` in `HiveMigrationService` (currently 1) versions the Hive boxes on disk. Changing a `@HiveField` bumps the second; changing the shape of exported JSON bumps the first.
- All user-facing currency formatting goes through `core/utils/currency_formatter.dart`; supported currencies and default fallback forex rates are in `AppConstants`.
- Imported JSON is validated through `core/utils/import_validator.dart` — don't bypass it when adding import paths. `BackupService.parse` (`services/backup_service.dart`) runs every check and decodes the whole file into model objects before anything is written; only then does `PortfolioWriteService.importBackup` write it. Settings › Import Data reads the picked file as bytes (`file_picker`, `withData: true`), never a path, so it works on web.
- Network services return a `Result`/`PriceResult` rather than throwing, and retry through `RetryHelper.withRetry` (`core/utils/retry_helper.dart`; 3 attempts, 1s → 2s backoff). The helper itself knows nothing about HTTP status: a 429 is excluded only because the caller passes `isRetriable`, which CoinGecko and CryptoCompare match against their `'Rate limit'` error string. A new caller that omits `isRetriable` will retry a 429 like any other failure.
- `ExportService` is a static-only class: the CSV row builders are pure functions so they can be unit-tested without the share sheet, and the capital-gains PDF splits STCG/LTCG on a simplified 12-month holding threshold.

## Phase 1 tracking (keep the WBS current)

Phase 1 (the Google Play launch, v1.0 → v1.0.x) is broken into 51 work packages in the Notion database **Phase 1 Tasks** (Onelunchdev › kashU, data source `collection://9fad9df9-483a-4764-b109-5f70e4c56ae5`). Each row has a WBS ID (`1.3.1` …), a `Status` of `TODO` / `In progress` / `Completed`, an owner, dates and a "Done when" test. The plan behind it sits next to it as the **KashU Roadmap** and **Phase 1 WBS** Notion pages; interactive versions: [roadmap](https://claude.ai/artifact/2V41gMcLjFEpff9HGeZcMm), [WBS](https://claude.ai/artifact/Lv8rwoNTPe62sXKzhb5aRi).

Update the board at these intervals through the Notion connector — if it isn't connected, say so instead of skipping the update:
- **Starting a task** — set its row to `In progress`.
- **Finishing a task** — set `Completed` only when its "Done when" is met, `flutter analyze --fatal-infos` and `flutter test` pass, and the change is committed; add the commit hash to the task page. If only a device check remains (fingerprint unlock, backup restore), leave it `In progress` and write down exactly what to test.
- **End of every working session** — reconcile the board with `git log`: unfinished work stays `In progress` with a one-line note of what is left, and a newly found loose end becomes a new row (next free ID in its deliverable) instead of a silent fix.
- **Every Friday** (task 1.1.5) — compare due dates with status. Window A (to 16 Nov 2026) has no slack, so a slip there moves the launch day for day; flag it.
- **When dates or scope change** — update the row's Start/Due, and the roadmap and WBS pages when a milestone moves.

Phase 1 git flow: one branch per deliverable off `staging` (`chore/release-engineering` = 1.2, `fix/p0-safety` = 1.3, `fix/p0-accuracy` = 1.4, later ones likewise), local commits with the WBS ID as the last line of the body, and nothing pushed until the owner asks.
