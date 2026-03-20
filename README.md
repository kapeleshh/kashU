e# KashU — Your Personal Investment Portfolio Tracker

**KashU** is a privacy-focused, offline-first Flutter app to track all your investments in one place — stocks, mutual funds, metals, crypto, deposits, and more — with live prices pulled automatically from free APIs.

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

### Other Features
- Multi-currency support (INR, USD, EUR, GBP, etc.)
- Transaction history (buy/sell/dividend)
- Platform grouping (Zerodha, Groww, etc.)
- Data export/import (JSON)
- Dark theme
- Offline-first (all data stored locally with Hive)

---

## 🚀 Getting Started

### Prerequisites
- Flutter SDK 3.11+
- Dart SDK 3.11+

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

---

## 📁 Project Structure

```
kashU/
├── lib/
│   ├── main.dart
│   ├── core/
│   │   ├── constants/          # Colors, strings, app constants
│   │   ├── theme/              # Dark theme
│   │   └── utils/              # Currency formatter
│   ├── data/
│   │   ├── models/             # Asset, Transaction (Hive models)
│   │   └── repositories/       # AssetRepository, TransactionRepository
│   ├── features/
│   │   ├── dashboard/          # Portfolio overview
│   │   ├── assets/             # Add/Edit/Detail screens
│   │   ├── transactions/       # Transaction history
│   │   └── settings/           # App settings
│   └── shared/
│       ├── providers/          # Riverpod providers
│       └── widgets/
│           ├── stock_search_field.dart       # Stock/ETF search with exchange filter
│           ├── mutual_fund_search_field.dart # MF search with plan/option filter
│           ├── crypto_search_field.dart      # Crypto search with market cap rank
│           └── fd_bond_input_field.dart      # FD/RD calculator widget
├── lib/services/
│   ├── gold_price_service.dart     # Gold & Silver COMEX prices
│   ├── yahoo_finance_service.dart  # Stock prices
│   ├── coingecko_service.dart      # Crypto prices + search
│   ├── mutual_fund_service.dart    # MFAPI.in NAV data
│   ├── stock_search_service.dart   # Yahoo Finance search
│   ├── currency_converter_service.dart  # Live forex rates
│   └── fd_bond_calculator.dart     # Compound interest math
├── proxy_server.py             # CORS proxy for web testing
├── build_apk.bat               # Windows APK build script
└── android/
    └── app/build.gradle.kts    # Android build config
```

---

## 🛠 Tech Stack

| Layer | Technology |
|-------|-----------|
| Framework | Flutter 3.41 |
| State Management | Riverpod 2.x |
| Local Database | Hive (offline-first) |
| Charts | fl_chart |
| HTTP | http package |
| Price APIs | Yahoo Finance, CoinGecko, MFAPI.in, open.er-api.com |

---

## 🌐 APIs Used (All Free, No API Key Required)

| API | Used For |
|-----|---------|
| `query1.finance.yahoo.com` | Stock prices, Gold/Silver COMEX prices, Stock search |
| `api.coingecko.com` | Crypto prices and search |
| `api.mfapi.in` | Indian mutual fund NAV (37,500+ schemes) |
| `open.er-api.com` | Live USD → INR forex rates |

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

- All portfolio data stored **locally on device** (Hive)
- No accounts, no login required
- No financial data sent to any server
- API calls are only for **price data** (no personal info)

---

## ☕ Support

If you find KashU useful, consider buying me a coffee!

[![Buy Me A Coffee](https://img.shields.io/badge/Buy%20Me%20A%20Coffee-Support-yellow?style=for-the-badge&logo=buy-me-a-coffee)](https://buymeacoffee.com/onelunchman13)

---

Made with ❤️ who value privacy and simplicity.
