# KashU - Your Personal Investment Portfolio Tracker

<p align="center">
  <img src="assets/icons/kashu_logo.png" width="120" alt="KashU Logo">
</p>

**KashU** is a privacy-focused, offline-first mobile app built with Flutter to track all your investments in one place.

## ✨ Features

### Phase 1 (MVP) - Completed
- **Multi-Asset Support**: Track Stocks, Mutual Funds, Gold, Crypto, Bonds, Fixed Deposits, Cash, and Real Estate
- **Multi-Currency**: Support for INR (default), USD, EUR, GBP, and more
- **Dashboard**: Total portfolio value, asset allocation chart, top gainers/losers
- **Asset Management**: Add, edit, delete investments with detailed information
- **Manual Price Updates**: Update current prices whenever you want
- **Transaction History**: Track all your buy/sell/dividend transactions
- **Platform Grouping**: View assets by type or by platform (Zerodha, Groww, etc.)
- **Data Export/Import**: Backup your data as JSON
- **Dark Theme**: Beautiful minimal dark UI
- **Offline-First**: All data stored locally on device

### Coming Soon (Phase 2+)
- 📊 Performance Charts & Trend Analysis
- 📝 Investment Journal
- 📈 Benchmark Comparison
- 🎯 Risk Score Calculator
- 🔄 Rebalancing Assistant
- 📅 Dividend Calendar
- 🔮 What-If Simulator
- 🔐 PIN/Biometric Authentication

## 🚀 Getting Started

### Prerequisites
- Flutter SDK (3.11+)
- Dart SDK (3.11+)

### Installation

1. Clone the repository:
```bash
git clone https://github.com/yourusername/kashu.git
cd kashu
```

2. Install dependencies:
```bash
flutter pub get
```

3. Generate Hive adapters:
```bash
dart run build_runner build --delete-conflicting-outputs
```

4. Run the app:
```bash
flutter run
```

## 📁 Project Structure

```
kashu/
├── lib/
│   ├── main.dart                 # App entry point
│   ├── core/
│   │   ├── constants/            # Colors, strings, constants
│   │   ├── theme/                # App theme
│   │   └── utils/                # Utility functions
│   ├── data/
│   │   ├── models/               # Data models (Asset, Transaction)
│   │   └── repositories/         # Data access layer
│   ├── features/
│   │   ├── dashboard/            # Dashboard screen
│   │   ├── assets/               # Assets list & detail screens
│   │   ├── transactions/         # Transactions screen
│   │   └── settings/             # Settings screen
│   └── shared/
│       ├── widgets/              # Reusable widgets
│       └── providers/            # Riverpod providers
├── assets/
│   ├── icons/
│   ├── images/
│   └── fonts/
└── test/
```

## 🛠 Tech Stack

- **Framework**: Flutter 3.x
- **State Management**: Riverpod
- **Local Database**: Hive
- **Charts**: fl_chart
- **Security**: flutter_secure_storage, local_auth

## 📱 Screenshots

Coming soon...

## 🔒 Privacy

KashU is designed with privacy in mind:
- All data is stored locally on your device
- No accounts required
- No data is sent to any servers
- Full control over your financial data

## 📄 License

This project is licensed under the MIT License.

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

---

Made with ❤️ for investors who value privacy and simplicity.
