# KashU — Your Personal Investment Portfolio Tracker

**KashU** is a privacy-focused, offline-first Flutter app to track all your investments in one place — stocks, mutual funds, metals, crypto, deposits, and more — with live prices pulled automatically from free APIs.

**▶︎ Try it: [kash-u.vercel.app](https://kash-u.vercel.app)** — no sign-up, nothing to install. Your portfolio stays in your own browser (see [Privacy](#-privacy)).

---

## ✨ Features

### Asset Types Supported

| Asset | Price Source | How it works |
|-------|-------------|--------------|
| **Stocks / ETFs** | Yahoo Finance | Search by company name → auto-fill symbol + live price |
| **Mutual Funds** | MFAPI.in (37,500+ Indian funds) | Search by fund name → auto-fill NAV |
| **Metals (Gold & Silver)** | COMEX via Yahoo Finance | Auto-fetch GC=F / SI=F → convert to INR/gram with Indian taxes |
| **Crypto** | CoinGecko | Search by name/symbol → live INR price |
| **Deposits (FD/RD)** | Compound interest calculator | Enter principal + rate OR maturity amount → auto-calculate current value |
| **Real Estate / Cash** | Manual | Enter value manually |

### Smart Search
- **Stocks**: Type a company name (e.g. "Reliance", "Apple") → live dropdown with exchange filter (NSE / BSE / NASDAQ / NYSE)
- **Mutual Funds**: Type fund name → filter by Direct/Regular and Growth/IDCW
- **Crypto**: Type coin name → results sorted by market cap rank

### Live Price Tracking
- **Gold**: COMEX GC=F → USD/gram → INR/gram with Budget 2024 taxes (BCD 5% + AIDC 1% + GST 3%)
- **Silver**: COMEX SI=F → USD/gram → INR/gram with silver taxes (BCD 10% + GST 3%)
- **Stocks**: Yahoo Finance real-time prices
- **Crypto**: CoinGecko live prices in INR

### Deposit Calculator
- **Fixed Deposit**: Enter principal + rate OR just the maturity amount (app back-calculates the rate)
- **Recurring Deposit**: Monthly installment with RD formula
- Shows: current value, maturity value, interest earned, progress bar

### Portfolio Dashboard
- Total portfolio value, total invested, gain/loss
- Asset allocation chart
- Top gainers / top losers

### Rebalancing
- Set a target allocation per asset type, see live drift against it, and get the buy/sell amounts that close the gap

### Tax Export
- Holdings and transactions as CSV
- Capital-gains PDF split into STCG / LTCG (12-month threshold) — hand it to your CA

### Other Features
- Multi-currency support (INR, USD, EUR, GBP, etc.) with a configurable base currency
- Transaction history (buy/sell/dividend)
- Platform grouping (Zerodha, Groww, etc.)
- 90-day price history — per-asset sparklines and day-over-day change
- Home-screen widget (Android AppWidget / iOS WidgetKit)
- App lock via biometrics or device PIN (mobile only)
- JSON backup export & import
- Light and dark themes, following your device
- Offline-first — all data stored locally in AES-256 encrypted Hive boxes

---

## 🚀 Getting Started

### Prerequisites
- Flutter SDK **3.41.6** (the version CI pins — matching it locally avoids analyzer drift)
- Dart SDK 3.4+

### Installation

```bash
git clone https://github.com/kapeleshh/kashU.git
cd kashU
flutter pub get
dart run build_runner build --delete-conflicting-outputs
```

### Run on Web (with live price APIs)

```bash
# Start the CORS proxy + serve the Flutter web build
python3 proxy_server.py
# Open http://localhost:8080 in your browser
```

The `proxy_server.py` is required for web because browsers block direct calls to Yahoo Finance, CoinGecko, and MFAPI.in. It proxies all API requests with CORS headers.

### Deploy to the Web (Vercel)

Deploys are manual: the Flutter bundle is built locally and the prebuilt `build/web` is uploaded. Pushing to GitHub does **not** deploy.

```bash
dart run build_runner build --delete-conflicting-outputs
rm -rf build/web && flutter build web --release
vercel login   # first time only
vercel         # preview deploy
vercel --prod  # promote to production
```

In production the CORS proxy is `api/proxy.py`, a Python serverless function that mirrors `proxy_server.py` behind a per-host path allowlist. It needs no environment variables.

> **Your data stays in your browser.** Nothing is stored on the server. The web build keeps your
> portfolio in the browser's IndexedDB, encrypted with a key held in that same browser — so clearing
> site data erases it, and a different browser or device starts empty.
>
> **On iOS, add it to your Home Screen.** Safari deletes a site's storage after 7 days without a
> visit; home-screen web apps are exempt from that. Either way, use **Settings → Export Data** to keep
> a JSON backup.

### Run on Android

**From Windows** (double-click):
```
build_apk.bat
```

APK output: `build\app\outputs\flutter-apk\app-debug.apk`

> **Note:** Android build tools are Windows `.exe` files and cannot run from WSL2. Use `build_apk.bat` from Windows PowerShell or File Explorer.

**From macOS/Linux:**
```bash
flutter build apk --debug
```

### Run on iOS
```bash
flutter build ios --debug
```

### Generating your release keystore (Android)

Release builds are signed from `android/key.properties`, which is **not**
checked in — you generate and keep your own keystore. Without it, release
builds fall back to debug signing (fine for local testing, not for
distribution).

```bash
keytool -genkey -v -keystore ~/kashu-release.jks -keyalg RSA \
  -keysize 2048 -validity 10000 -alias kashu
```

Then create `android/key.properties`:

```properties
storeFile=/absolute/path/to/kashu-release.jks
storePassword=<store password>
keyAlias=kashu
keyPassword=<key password>
```

Both the keystore and `key.properties` are gitignored. Keep backups — a lost
keystore means you cannot update a published app.

---

## 📁 Project Structure

```
kashU/
├── lib/
│   ├── main.dart
│   ├── core/
│   │   ├── config/             # Build-time config, crash-reporting consent
│   │   ├── constants/          # Colors, strings, app constants
│   │   ├── theme/              # Light + dark "C·Soft" theme
│   │   └── utils/              # Currency formatter, platform URLs, file saver
│   ├── data/
│   │   ├── models/             # Asset, Transaction (Hive models)
│   │   ├── migration/          # Hive schema versioning
│   │   └── repositories/       # Asset/Transaction repos + cross-box writes
│   ├── features/
│   │   ├── dashboard/          # Portfolio overview
│   │   ├── assets/             # Add/Edit/Detail screens
│   │   ├── transactions/       # Transaction history
│   │   ├── rebalancing/        # Target allocations and drift
│   │   ├── export/             # Tax export (CSV + capital-gains PDF)
│   │   ├── auth/               # App lock screen
│   │   ├── onboarding/         # First-run flow
│   │   └── settings/           # App settings
│   └── shared/
│       ├── providers/          # Riverpod providers
│       └── widgets/
│           ├── stock_search_field.dart       # Stock/ETF search with exchange filter
│           ├── mutual_fund_search_field.dart # MF search with plan/option filter
│           ├── crypto_search_field.dart      # Crypto search with market cap rank
│           └── fd_bond_input_field.dart      # FD/RD calculator widget
├── lib/services/
│   ├── price_update_service.dart   # Routes each asset to the right price API
│   ├── gold_price_service.dart     # Gold & Silver COMEX prices + Indian taxes
│   ├── yahoo_finance_service.dart  # Stock prices
│   ├── stooq_service.dart          # Stock fallback when Yahoo fails
│   ├── coingecko_service.dart      # Crypto prices + search
│   ├── cryptocompare_service.dart  # Crypto fallback
│   ├── mutual_fund_service.dart    # MFAPI.in NAV data
│   ├── stock_search_service.dart   # Yahoo Finance search
│   ├── currency_converter_service.dart  # Live forex rates
│   ├── price_cache_service.dart    # Last-known prices for offline use
│   ├── price_history_service.dart  # 90-day daily snapshots
│   ├── export_service.dart         # CSV + capital-gains PDF
│   ├── widget_update_service.dart  # Home-screen widget bridge
│   └── fd_bond_calculator.dart     # Compound interest math
├── test/                       # Mirrors lib/ — run with `flutter test`
├── api/proxy.py                # CORS proxy as a Vercel serverless function
├── vercel.json                 # Web deployment config
├── .vercelignore               # Allowlist of what gets uploaded
├── proxy_server.py             # Same proxy, for local web development
├── build_apk.bat               # Windows APK build script
└── android/
    └── app/build.gradle.kts    # Android build config
```

---

## 🛠 Tech Stack

| Layer | Technology |
|-------|-----------|
| Framework | Flutter 3.41.6 |
| State Management | Riverpod 2.x |
| Local Database | Hive — offline-first, AES-256 encrypted |
| Charts | fl_chart |
| HTTP | http package |
| Export | pdf, printing, csv |
| Crash reporting | Sentry (opt-in, off by default) |
| Web hosting | Vercel — static build + Python serverless proxy |
| Price APIs | Yahoo Finance, Stooq, CoinGecko, CryptoCompare, MFAPI.in, open.er-api.com |

---

## 🌐 APIs Used (All Free, No API Key Required)

| API | Used For |
|-----|---------|
| `query1.finance.yahoo.com` | Stock prices, Gold/Silver COMEX prices, Stock search |
| `api.coingecko.com` | Crypto prices and search |
| `stooq.com` | Stock/metal price fallback when Yahoo is unavailable |
| `api.mfapi.in` | Indian mutual fund NAV (37,500+ schemes) |
| `min-api.cryptocompare.com` | Crypto price fallback when CoinGecko is rate-limited |
| `open.er-api.com` | Live USD → INR forex rates |

All of these are read-only `GET` requests for public market data. On the web build they are routed
through a same-origin proxy that only permits the hosts and paths listed above.

---

## 💰 Gold & Silver Price Calculation

```
COMEX GC=F (Gold) → $4,700/troy oz
÷ 31.1035 = $151.1/gram
× ₹93.07 (live forex) = ₹14,057/gram (base)
× (1 + 0.05 + 0.01) × (1 + 0.03) = ₹15,347/gram (with taxes)

Indian Gold Taxes (Budget 2024):
  BCD: 5%  |  AIDC: 1%  |  GST: 3%  |  Effective: ~9.18%

Indian Silver Taxes:
  BCD: 10%  |  GST: 3%  |  Effective: ~13.30%
```

---

## 🔒 Privacy

- All portfolio data is stored **locally**, in AES-256 encrypted Hive boxes
- No accounts, no login, no analytics, no tracking
- **No financial data is ever transmitted.** Every network call is a `GET` for public market data —
  there is no endpoint, anywhere, that accepts your portfolio
- Crash reporting (Sentry) is **opt-in and off by default**, and even when enabled it drops HTTP
  breadcrumbs so request URLs containing your holdings are never sent
- **On mobile**, the encryption key lives in the iOS Keychain / Android Keystore
- **On web**, the key lives in the browser's `localStorage` alongside the data in IndexedDB. That is
  obfuscation at rest rather than a true keychain, so the mobile app is the stronger place to keep
  your only copy — and keep a JSON backup either way

---

## ☕ Support

If you find KashU useful, consider buying me a coffee!

[![Buy Me A Coffee](https://img.shields.io/badge/Buy%20Me%20A%20Coffee-Support-yellow?style=for-the-badge&logo=buy-me-a-coffee)](https://buymeacoffee.com/onelunchman13)

---

Made with ❤️ who value privacy and simplicity.
