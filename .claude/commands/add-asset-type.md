---
description: Add a new AssetType end-to-end — model, price routing, search widget, tests
allowed-tools: Bash, Read, Edit, Glob, Grep
---

Add a new asset type to KashU. The type to add (and its price source, if any):
$ARGUMENTS

This is a cross-cutting change. Touch every site below — the Dart compiler's
exhaustive `switch` checks will flag the model ones, but price routing and the UI
will silently misbehave if skipped.

1. **Enum + model** — `lib/data/models/asset_type.dart`. Add the value with the
   **next unused `@HiveField` number** (do not reuse/reorder). Fill in all
   exhaustive switches in `AssetTypeExtension`: `displayName`, `icon`, `color`,
   `unitLabel`. Add any new label to `core/constants/app_strings.dart` and color to
   `core/constants/app_colors.dart`.

2. **Schema migration** — the model changed, so follow the
   `/hive-migration` steps: bump `_currentSchemaVersion` and add a `_migrations`
   entry (a no-op is fine for a pure enum addition).

3. **Price routing rules** — `lib/services/price_service.dart`, class `PriceSymbols`:
   add the new type to the `supportsAutoTracking`, `symbolHint`, and `defaultSymbol`
   switches. If it is NOT auto-tracked (like cash/realEstate), return false / "manual"
   and you can skip step 4.

4. **Price fetching** — `lib/services/price_update_service.dart`. Route the type in
   both `refreshSinglePrice` and the bulk `updateAllPrices` flow (which partitions by
   `AssetType`). Reuse an existing API where possible:
   - crypto → CoinGecko · gold/silver → `GoldPriceService` · stocks/bonds/funds →
     Yahoo Finance (Stooq fallback).
   - If it needs a NEW API, add a stateless service under `lib/services/` with
     constructor-injected deps + a `Provider` in
     `lib/shared/providers/portfolio_provider.dart` (the wiring-hub pattern). Preserve:
     pre-fetched exchange rates, convert into the asset's stored currency, fall back to
     `PriceCacheService` on failure, throttle stock-style calls (~300ms).

5. **Search/entry UI** — if the type is searchable, add a field widget under
   `lib/shared/widgets/` mirroring `stock_search_field.dart` /
   `crypto_search_field.dart`, and wire it into the add/edit asset screen in
   `lib/features/assets/`.

6. **Tests** — add a test under `test/services/` for any new service using the
   mocktail + fake-HTTP-client constructor pattern. Cover currency conversion and
   the cache fallback.

7. **Verify** — run `/regen` (build_runner → `flutter analyze --fatal-infos` →
   `flutter test`).

Finish with a checklist of which of the 7 steps you changed and which were N/A
(e.g. manual-only types skip 4 and 5).
