# feat: Live gold price tracking with automatic INR/gram conversion

## Summary

This PR introduces a complete **live gold price tracking system** for the kashU portfolio app. When a user adds or views a gold asset, the app automatically fetches the current international gold price, converts it to Indian Rupees per gram using live forex rates, and applies the correct Indian import taxes — all transparently and in real time.

---

## Motivation

Gold is one of the most common investment assets in India, yet tracking its current market value requires knowing:
1. The international COMEX spot price (USD/troy oz)
2. The live USD → INR exchange rate
3. Indian import duties and GST (updated to Budget 2024 rates)

Previously, users had to manually look up and enter the gold price. This PR automates the entire pipeline.

---

## What Changed

### New Services

| File | Description |
|------|-------------|
| `lib/services/gold_price_service.dart` | Core gold price engine: fetches COMEX GC=F, converts USD/oz → INR/gram, applies Indian taxes |
| `lib/services/yahoo_finance_service.dart` | Fetches stock/ETF/gold prices from Yahoo Finance API; routes through CORS proxy on web |
| `lib/services/currency_converter_service.dart` | Fetches live USD exchange rates from open.er-api.com; 30-min in-memory cache; CORS proxy on web |
| `lib/services/price_service.dart` | Abstract `PriceService` interface + `PriceSymbols` helpers (COMEX symbol, auto-tracking support) |
| `lib/services/price_update_service.dart` | Orchestrates bulk price refresh: routes gold → `GoldPriceService`, crypto → CoinGecko, stocks → Yahoo Finance |
| `lib/services/coingecko_service.dart` | Fetches cryptocurrency prices from CoinGecko API |
| `proxy_server.py` | Python HTTP server that serves the Flutter web build AND proxies Yahoo Finance + open.er-api.com requests to bypass browser CORS restrictions |

### Tax Configuration (Budget 2024)

The `GoldTaxConfig` class applies the correct Indian import taxes as updated in the **Union Budget 2024 (effective July 23, 2024)**:

| Tax | Old Rate | New Rate |
|-----|----------|----------|
| Basic Customs Duty (BCD) | 10% | **5%** |
| Agriculture Infrastructure & Development Cess (AIDC) | 5% | **1%** |
| GST | 3% | 3% (unchanged) |
| **Effective total** | 18.45% | **9.18%** |

### UI Changes

**Add Asset screen** (`lib/features/assets/add_asset_screen.dart`):
- Selecting the **Gold** chip now instantly:
  - Auto-fills the symbol field with `GC=F`
  - Triggers a live price fetch in the background
  - Shows a loading spinner in the symbol field
  - Populates the **Current Price** field with the fetched INR/gram value
  - Displays `✅ Live gold price: ₹X/gram` on success

**Asset Detail screen** (`lib/features/assets/asset_detail_screen.dart`):
- Gold assets show a **"Live Gold Price"** card with:
  - "Fetch Live Price" button to pull the current price on demand
  - Displays the current price per gram in gold
  - "Apply Live Price" button to save it to the asset with one tap
  - Manual price entry still available as fallback

### Repository Fix

**`lib/data/repositories/asset_repository.dart`**:
- `updateAssetPrice` now uses `asset.copyWith() + box.put(id, updated)` instead of `asset.save()`
- `asset.save()` can fail silently on web (Hive IndexedDB) when the object reference is a snapshot rather than a live `HiveObject`

### Provider Updates

**`lib/shared/providers/portfolio_provider.dart`**:
- Added `goldPriceServiceProvider` (singleton with shared `CurrencyConverterService` for cache reuse)
- Added `priceUpdateServiceProvider` for bulk refresh orchestration

---

## Architecture

```
User taps "Gold" chip
        │
        ▼
AddAssetScreen._fetchGoldPrice()
        │
        ▼
GoldPriceService.fetchGoldPriceBreakdown(targetCurrency: 'INR')
        │
        ├─► YahooFinanceService.fetchPrice('GC=F')
        │         │
        │         └─► [Web] http://localhost:8080/proxy?url=https://query1.finance.yahoo.com/...
        │             [Mobile/Desktop] Direct HTTPS call
        │             Returns: USD per troy oz
        │
        ├─► CurrencyConverterService.fetchRates()
        │         │
        │         └─► [Web] http://localhost:8080/proxy?url=https://open.er-api.com/v6/latest/USD
        │             [Mobile/Desktop] Direct HTTPS call
        │             Returns: USD → INR rate (cached 30 min)
        │
        └─► Apply GoldTaxConfig.india (BCD 5% + AIDC 1% + GST 3%)
                  │
                  ▼
            Final price in ₹/gram → auto-filled into Current Price field
```

---

## Testing

- [x] Proxy server verified: `curl http://localhost:8080/proxy?url=...` returns live COMEX price
- [x] Gold price pipeline verified end-to-end: `$4,698/oz → ₹93.07/USD → ₹15,347/gram`
- [x] Tax calculation verified against Budget 2024 rates (within 1.7% of market price)
- [x] `flutter analyze` passes with no errors on all modified files
- [x] Web build succeeds (`flutter build web`)
- [x] Asset price update persists correctly on web (Hive IndexedDB)

---

## How to Run (Web)

```bash
# From project root — starts the CORS proxy + serves the Flutter web build
python3 proxy_server.py
# Open http://localhost:8080 in your browser
```

---

## Files Changed

```
14 files changed, 1799 insertions(+), 64 deletions(-)

New files:
  lib/services/gold_price_service.dart         (+242)
  lib/services/currency_converter_service.dart (+179)
  lib/services/price_update_service.dart       (+303)
  lib/services/yahoo_finance_service.dart      (+119)
  lib/services/coingecko_service.dart          (+142)
  lib/services/price_service.dart              (+121)
  proxy_server.py                              (+105)

Modified files:
  lib/features/assets/add_asset_screen.dart    (+173/-14)
  lib/features/assets/asset_detail_screen.dart (+280/-44)
  lib/features/dashboard/dashboard_screen.dart (+140/-6)
  lib/shared/providers/portfolio_provider.dart (+44/-4)
  lib/data/repositories/asset_repository.dart  (+11/-4)
  pubspec.yaml                                 (+3)
  lib/features/settings/settings_screen.dart   (-1)
```

---

## Commits

| Hash | Message |
|------|---------|
| `505000a` | refactor(ui): remove technical pricing details from gold price UI |
| `d8bf251` | feat(add-asset): auto-fill symbol and fetch live price when Gold type selected |
| `f34a5e9` | chore: update generated plugin registrants for new dependencies |
| `99276a9` | fix(repo): use box.put for reliable asset price updates on web |
| `3d52830` | feat(ui): add live gold price card with full breakdown in asset detail screen |
| `6f85c3c` | feat(gold): implement live gold price tracking with COMEX→INR conversion |
| `2efcddb` | feat(gold): implement country-aware gold price tracking |
| `b6aac64` | feat(services): add CurrencyConverterService for live exchange rates |
| `84fb203` | chore(deps): add http package for price tracking API calls |
| `9880913` | fix(settings): remove unused transaction_repository import |

---

## Checklist

- [x] Code compiles without errors (`flutter analyze` — no issues)
- [x] Web build succeeds (`flutter build web`)
- [x] No hardcoded secrets or API keys
- [x] Tax rates updated to current Indian Budget 2024 rates
- [x] CORS handled correctly for web platform (`kIsWeb` routing)
- [x] Async `BuildContext` usage is safe (captured before `await` gaps)
- [x] Hive writes use `box.put()` for cross-platform reliability
- [x] User-facing UI shows clean prices (no technical jargon)
- [x] Fallback rates available for offline mode
- [x] 30-minute forex rate cache to avoid redundant API calls

---

> **Note for reviewers:** The `proxy_server.py` is a development/web-testing utility only. On mobile/desktop builds, the Flutter app calls the APIs directly without the proxy.
