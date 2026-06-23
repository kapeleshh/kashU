# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

KashU is a privacy-focused, offline-first Flutter app for tracking an investment portfolio (stocks, mutual funds, metals, crypto, deposits, real estate, cash). All portfolio data lives locally in encrypted Hive boxes; the network is only used to fetch price/forex data.

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

CI (`.github/workflows/ci.yml`) runs on push to `main`/`p0-improvements` and PRs to `main`: pub get → build_runner → `flutter analyze --fatal-infos` → `flutter test --coverage`. `--fatal-infos` means even lint infos fail the build. CI pins **Flutter 3.41.6 (stable)** — match this locally to avoid analyzer drift.

### Running on each platform

- **Web**: requires the CORS proxy. Browsers block direct calls to Yahoo Finance / CoinGecko / MFAPI.in, so `python3 proxy_server.py` serves `build/web` and proxies allowed hosts via `/proxy?url=...`. Run `flutter build web` first, then the proxy at `http://localhost:8080`.
- **Android**: `flutter build apk --debug` on macOS/Linux. On Windows use `build_apk.bat` (the Android build tools are Windows `.exe` and cannot run from WSL2).
- **iOS/macOS**: `flutter build ios --debug` / standard Flutter. Podfiles for ios/macos may be untracked locally.

### Crash reporting (Sentry)

Sentry is a no-op unless a DSN is provided at build time:
```bash
flutter build apk --dart-define=SENTRY_DSN=https://xxx@sentry.io/yyy --dart-define=APP_ENV=production
```
`AppConfig` (`lib/core/config/app_config.dart`) reads these via `String.fromEnvironment`. `main()` only wraps the app in `SentryFlutter.init` when `AppConfig.isSentryEnabled`.

## Architecture

Layered structure under `lib/`:
- `core/` — config, constants, theme, and utils (Result type, retry helper, import validation, platform/currency formatting). No app logic.
- `data/` — Hive `models/` (+ generated adapters), `repositories/` (Hive access), and `migration/` (schema versioning).
- `services/` — all network/price/business logic. Stateless services, instantiated via Riverpod providers.
- `features/` — one folder per screen/flow (dashboard, assets, transactions, settings, auth, onboarding).
- `shared/` — `providers/` (Riverpod) and reusable `widgets/` (the asset search fields, charts).

### State management — Riverpod

`lib/shared/providers/portfolio_provider.dart` is the wiring hub: it constructs repositories and services and exposes them as providers, plus derived state like `portfolioSummaryProvider` (FutureProvider), `baseCurrencyProvider`, and price-refresh status providers. Services take their dependencies via constructor (with defaults) so they're testable — providers inject the shared singletons. When adding a service, follow this pattern: constructor-injected deps + a `Provider` in this file.

### Persistence — Hive (encrypted)

Four boxes, all opened in `main.dart` `_bootstrap()`: `assets_box`, `transactions_box`, `settings_box`, `price_cache_box` (names in `AppConstants`). All boxes are AES-encrypted with a 256-bit key generated once and stored in the platform keychain/keystore via `flutter_secure_storage` (`_loadOrCreateCipher`). If box opening fails (corruption/full disk), the app shows `_DatabaseErrorApp` instead of crashing.

**Schema migrations** (`data/migration/hive_migration_service.dart`): when you add/change a `@HiveField` on a model, bump `_currentSchemaVersion` and add a matching entry to the `_migrations` map. `runMigrations()` runs pending steps on startup after boxes open. Model `typeId`s are fixed (Asset=2, etc.) — never reuse or reorder field numbers.

Repositories (`AssetRepository`, `TransactionRepository`) are the only place that touches Hive boxes directly. Derived portfolio math (`totalInvested`, `currentValue`, `gainLoss`) lives as getters on the `Asset` model, not in repositories.

### Price tracking — the core domain logic

`PriceService` (`services/price_service.dart`) is the abstract interface; `PriceSymbols` holds the per-`AssetType` routing rules (which types support auto-tracking, default symbols, input hints).

`PriceUpdateService` (`services/price_update_service.dart`) orchestrates a full refresh: it routes each asset to the right API by `AssetType` — crypto → CoinGecko, gold → `GoldPriceService`, everything else → Yahoo Finance with **Stooq as fallback**. Key behaviors to preserve when editing:
- Exchange rates are pre-fetched once per refresh and reused (`CurrencyConverterService`, backed by live USD→INR forex from `open.er-api.com`).
- Prices are converted into each asset's stored currency before saving.
- On API failure, it falls back to the last cached price (`PriceCacheService`, `price_cache_box`) before counting an asset as failed.
- Stock/bond refreshes are throttled (300ms between calls) to avoid rate limiting.

**Gold/silver pricing is computed, not fetched directly.** `GoldPriceService` fetches COMEX `GC=F`/`SI=F` (USD/troy oz) via Yahoo, converts oz→gram (÷31.1035) and USD→target currency via live forex, then applies Indian import duties + GST (`GoldTaxConfig.india` ≈ 9.18% for gold) only when the target currency is INR. This tax math is intentional and tested — see `test/services/gold_price_service_test.dart`.

### App startup flow

`main()` → `_bootstrap()`: error handlers → Hive init + register adapters → load/create cipher → open boxes (or error screen) → run migrations → read settings flags → `runApp`. `KashUApp` chooses the home screen by priority: onboarding > lock screen (biometric/PIN auth) > dashboard.

## Conventions

- Tests use `mocktail` and live under `test/`, mirroring `lib/services/`. Service tests inject fake HTTP clients / dependencies via the constructor params.
- All user-facing currency formatting goes through `core/utils/currency_formatter.dart`; supported currencies and default fallback forex rates are in `AppConstants`.
- Imported JSON is validated through `core/utils/import_validator.dart` — don't bypass it when adding import paths.
