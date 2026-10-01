# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

KashU is a privacy-focused, offline-first Flutter app for tracking an investment portfolio (stocks, mutual funds, metals, crypto, deposits, real estate, cash). All portfolio data lives locally in encrypted Hive boxes; the network is only used to fetch price/forex data.

`docs/TECHNICAL_DECISIONS.md` records the *why* behind the Flutter / Riverpod / Hive choices, the data-model shape, and the Phase-1 security posture — read it before relitigating those decisions.

## Commands

```bash
flutter pub get                                          # install deps
dart run build_runner build --delete-conflicting-outputs # regenerate *.g.dart (REQUIRED, see below)
flutter analyze --fatal-infos                            # lint + type check (CI gate)
flutter test                                             # run all tests
flutter test test/services/gold_price_service_test.dart  # run a single test file
flutter test --name "applies Indian taxes"               # run tests matching a name
```

**Code generation is mandatory before analyze/test/run.** Hive adapters (`*.g.dart`) are generated from `@HiveType`/`@HiveField` annotations and are *not* committed in a build-ready state across all environments — CI runs `build_runner` before `flutter analyze`. After editing any model in `lib/data/models/` (or adding Riverpod codegen), rerun `build_runner` or the build breaks with missing-symbol errors.

CI (`.github/workflows/ci.yml`) runs on push to `main`/`staging`/`p0-improvements` and PRs to `main`/`staging`. Two jobs:
1. `analyze-and-test` — pub get → build_runner → `flutter analyze --fatal-infos` → `flutter test --coverage`. `--fatal-infos` means even lint infos fail the build.
2. `build-android` — runs only if the first passes; Java 17 + `flutter build apk --release` (debug-signed until a release keystore is wired in from secrets).

CI pins **Flutter 3.41.6 (stable)** — match this locally to avoid analyzer drift.

### Repo automation (`.claude/`)

Two hooks in `.claude/settings.json` enforce the rules above mechanically, so they usually don't need running by hand:
- **PostToolUse** (`regen-on-model-change.sh`) — reruns `build_runner` after any edit to a hand-written file in `lib/data/models/`.
- **Stop** (`analyze-on-stop.sh`) — runs `flutter analyze --fatal-infos` before a turn ends, but only when there are uncommitted `.dart` changes.

Project slash commands live in `.claude/commands/` (`/regen`, `/hive-migration`, `/add-asset-type`, `/triage`, `/fix-web-bug`, `/commit`, `/pr`) and encode the canonical multi-step flows.

### Running on each platform

- **Web**: requires a CORS proxy — browsers block direct calls to Yahoo Finance / CoinGecko / MFAPI.in / open.er-api.com. Locally: `flutter build web`, then `python3 proxy_server.py`, which serves `build/web` and proxies at `http://localhost:8080`. Deployed: Vercel (see below). Both expose the **same** contract, `/api/proxy?url=<encoded absolute https URL>` (`proxy_server.py` also still answers the legacy `/proxy?` path).
- **Android**: `flutter build apk --debug` on macOS/Linux. On Windows use `build_apk.bat` (the Android build tools are Windows `.exe` and cannot run from WSL2).
- **iOS/macOS**: `flutter build ios --debug` / standard Flutter. Podfiles for ios/macos may be untracked locally.

### Web deployment (Vercel)

`vercel.json` publishes the prebuilt `build/web` as static output (`buildCommand` is empty — build locally and deploy; git auto-deploys are disabled) and rewrites everything except `/api/*` to `index.html`. `flutter_bootstrap.js`, `flutter_service_worker.js`, `version.json`, and `index.html` are served `no-cache` so clients don't pin a stale build.

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

### Persistence — Hive (encrypted)

Five boxes, all opened in `main.dart` `_bootstrap()`: `assets_box`, `transactions_box`, `settings_box`, `price_cache_box`, `price_history_box` (names in `AppConstants`). All boxes are AES-encrypted with a 256-bit key generated once and stored in the platform keychain/keystore via `flutter_secure_storage` (`_loadOrCreateCipher`). If box opening fails (corruption/full disk), the app shows `_DatabaseErrorApp` instead of crashing.

**On web the storage story is weaker, and it is not guarded by `kIsWeb`.** `Hive.initFlutter()` has no web branch, so each box becomes its own **IndexedDB** database, and `flutter_secure_storage_web` keeps the AES key — plus the WebCrypto key that wraps it — in the same origin's `localStorage`. That is obfuscation at rest, not a keychain. Consequences worth knowing before touching web behaviour: clearing site data destroys the portfolio outright; iOS Safari evicts the storage of a site not visited for 7 days unless it was added to the Home Screen; and the app lock is inert (the Settings toggle is hidden and `AuthResult.notAvailable` simply unlocks). There is no server-side copy of anything, so an export is the only backup a web user has.

**Writing a file goes through `core/utils/file_saver.dart`.** It is a conditional export — `file_saver_io.dart` writes to the documents directory and opens the share sheet, `file_saver_web.dart` hands the bytes to the browser as a download. **Never import `dart:io` or `path_provider` outside `file_saver_io.dart`**: both compile on web and then throw at runtime (`getApplicationDocumentsDirectory()` has no web implementation, `File` writes raise `UnsupportedError` under dart2js), which is exactly how every web export silently failed into an `Export failed:` SnackBar before this split existed. `exportCapitalGainsPdf` is currently unreferenced — the tax screen calls `previewCapitalGainsPdf`, which goes to the browser/OS print dialog via `Printing.layoutPdf`.

`settings_box` doubles as the app's general key-value store, not just user preferences: the `AppConstants.key*` entries (base currency, app lock, schema version, crash-reporting consent, backup nudge), the rebalancing targets under `rebal_{assetTypeName}` keys, and the `PortfolioWriteService` pending-write markers all live there.

**Schema migrations** (`data/migration/hive_migration_service.dart`): when you add/change a `@HiveField` on a model, bump `_currentSchemaVersion` and add a matching entry to the `_migrations` map. `runMigrations()` runs pending steps on startup after boxes open. Currently at version 1 with no migration steps. Model `typeId`s are fixed — `AssetType=0`, `TransactionType=1`, `Asset=2`, `Transaction=3` — never reuse or reorder field numbers.

Repositories (`AssetRepository`, `TransactionRepository`) are the only place that touches Hive boxes directly. Derived portfolio math (`totalInvested`, `currentValue`, `gainLoss`) lives as getters on the `Asset` model, not in repositories.

**Cross-box writes go through `PortfolioWriteService`** (`data/repositories/portfolio_write_service.dart`), not the two repositories directly. Hive has no cross-box transactions, so a crash between the two halves of a combined write (add asset + log its BUY; delete asset + its transactions; Clear All Data) can leave the boxes inconsistent. This service compensates on failed adds and writes pending-write markers into the settings box for deletes, which `completeInterruptedWrites()` finishes on the next launch (`main.dart`). It only ever cleans up *marked* writes — orphaned transactions from any other source are real user history (they feed the Activity screen and tax exports) and must not be touched.

### Price tracking — the core domain logic

`PriceService` (`services/price_service.dart`) is the abstract interface; `PriceSymbols` holds the per-`AssetType` routing rules (which types support auto-tracking, default symbols, input hints).

`PriceUpdateService` (`services/price_update_service.dart`) orchestrates a full refresh, routing each asset by `AssetType` into four separate batches:
- **crypto** → CoinGecko, then `CryptoCompareService` for whatever failed as **one batched call** (not per asset), then the cache. The app stores CoinGecko ids, so `_idToTicker` maps `bitcoin`→`BTC`; unmapped ids fail straight through to the cache. CryptoCompare reports errors as HTTP 200 with `{"Response": "Error"}`, so the body must be checked.
- **gold/silver** → `GoldPriceService` (see below).
- **mutual funds** → `MutualFundService` (MFAPI.in, keyed by AMFI scheme code — not Yahoo).
- **everything else** (stocks, bonds) → Yahoo Finance with **Stooq as fallback**.

Key behaviors to preserve when editing:
- Exchange rates are pre-fetched once per refresh and reused (`CurrencyConverterService`, backed by live USD→INR forex from `open.er-api.com`).
- Prices are converted into each asset's stored currency before saving.
- On API failure, it falls back to the last cached price (`PriceCacheService`, `price_cache_box`) before counting an asset as failed.
- Stock/bond refreshes are throttled (300ms between calls) to avoid rate limiting.

**Gold/silver pricing is computed, not fetched directly.** `GoldPriceService` fetches COMEX `GC=F`/`SI=F` (USD/troy oz) via Yahoo, converts oz→gram (÷31.1035) and USD→target currency via live forex, then applies Indian import duties + GST (`GoldTaxConfig.india` ≈ 9.18% for gold) only when the target currency is INR. This tax math is intentional and tested — see `test/services/gold_price_service_test.dart`.

**Never call `kIsWeb` from a service to pick a URL.** `PlatformConfig.buildUrl()` (`core/utils/platform_config.dart`) is the single place that decides between the direct URL (mobile/desktop) and the same-origin `/api/proxy?url=…` route (web), resolved against `Uri.base` so it works unchanged on localhost, Vercel previews, and production.

### Portfolio history and the home-screen widget

After each successful refresh the dashboard (`features/dashboard/dashboard_screen.dart`) fans out to two side effects:
- `PriceHistoryService.recordDailySnapshot()` writes one `DailySnapshot` per day into `price_history_box`, keyed `yyyy-MM-dd`, pruned to a 90-day `retention` window. `total` is in the base currency; `assetValues` are in each asset's **own** currency, because they only feed per-asset sparklines where the shape matters, not the unit. This also backs the day-over-day change (`previousDayTotal`).
- `WidgetUpdateService.updatePortfolioWidget()` writes formatted values to shared native storage and pokes the Android `AppWidgetProvider` / iOS WidgetKit app group. It returns early on web (`home_widget` has no web implementation and would throw `MissingPluginException`).

### Theming — "C·Soft"

`core/theme/app_theme.dart` builds both `lightTheme` and `darkTheme`; `main.dart` runs `ThemeMode.system` and every screen is theme-aware. **Don't hardcode colors, radii, shadows or fonts in widgets:**
- `AppColors` (`core/constants/app_colors.dart`) — the semantic tokens (`background`, `surface`, `textPrimary`, …) hold the **dark** values; their light counterparts live under `light*` tokens and are picked inside `AppTheme._build`. Per-`AssetType` colors (`stockColor`, `cryptoColor`, …) and the brand gradients live here too.
- `AppRadii` / `AppShadows` (`core/theme/app_decorations.dart`) — the shared corner radii and the soft purple-tinted shadows/glows.
- Typography is **Quicksand for headings, Plus Jakarta Sans for body/labels**, reached through the `TextTheme` or the `AppTheme.heading()` / `AppTheme.body()` helpers — never `GoogleFonts.*` directly in a widget.

### App startup flow

`main()` → `_bootstrap()`: error handlers → Hive init + register adapters → load/create cipher → open boxes (or error screen) → run migrations → finish interrupted cross-box writes → read settings flags → `runApp`. `KashUApp` chooses the home screen by priority: onboarding > lock screen (biometric/PIN auth) > dashboard.

## Conventions

- Tests use `mocktail` and live under `test/`, mirroring the `lib/` layout. Service tests inject fake HTTP clients / dependencies via the constructor params; Hive-backed services take a `Box?` override for the same reason.
- All user-facing currency formatting goes through `core/utils/currency_formatter.dart`; supported currencies and default fallback forex rates are in `AppConstants`.
- Imported JSON is validated through `core/utils/import_validator.dart` — don't bypass it when adding import paths.
- Network services return a `Result`/`PriceResult` rather than throwing, and retry through `core/utils/retry_helper.dart`, which deliberately does **not** retry a 429.
- `ExportService` is a static-only class: the CSV row builders are pure functions so they can be unit-tested without the share sheet, and the capital-gains PDF splits STCG/LTCG on a simplified 12-month holding threshold.
