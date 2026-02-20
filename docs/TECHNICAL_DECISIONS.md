# KashU - Technical Architecture & Decision Document

## Table of Contents
1. [Executive Summary](#executive-summary)
2. [Technology Stack Overview](#technology-stack-overview)
3. [Framework Selection: Flutter](#framework-selection-flutter)
4. [State Management: Riverpod](#state-management-riverpod)
5. [Local Database: Hive](#local-database-hive)
6. [Architecture Pattern](#architecture-pattern)
7. [UI/UX Decisions](#uiux-decisions)
8. [Data Models Design](#data-models-design)
9. [Security Considerations](#security-considerations)
10. [Challenges & Mitigations](#challenges--mitigations)
11. [Performance Considerations](#performance-considerations)
12. [Future Scalability](#future-scalability)
13. [Dependencies Analysis](#dependencies-analysis)
14. [Testing Strategy](#testing-strategy)
15. [Key Learnings](#key-learnings)

---

## Executive Summary

**KashU** is a personal investment portfolio tracker built with Flutter, designed with privacy and offline-first principles. This document explains every technical decision made during Phase 1 (MVP) development, including why certain tools were chosen, what alternatives were considered, and the tradeoffs involved.

**Primary Goals:**
- Privacy-focused (data stays on device)
- Offline-first (works without internet)
- Cross-platform (iOS, Android from single codebase)
- Minimal, dark UI
- Fast performance on mid-range devices

---

## Technology Stack Overview

| Layer | Technology | Version | Purpose |
|-------|------------|---------|---------|
| Framework | Flutter | 3.x | Cross-platform UI |
| Language | Dart | 3.11 | Programming language |
| State Management | Riverpod | 2.4.9 | Reactive state |
| Local Database | Hive | 2.2.3 | NoSQL local storage |
| Charts | fl_chart | 0.66.2 | Data visualization |
| Security | flutter_secure_storage | 9.0.0 | Encrypted storage |
| Authentication | local_auth | 2.1.8 | Biometric auth |
| Utilities | intl, uuid | Latest | Formatting, IDs |

---

## Framework Selection: Flutter

### Why Flutter?

**Decision:** Use Flutter instead of native iOS/Android or React Native.

**Reasoning:**

1. **Single Codebase**: Write once, deploy to iOS, Android, Web, and Desktop. For a personal project, maintaining separate iOS/Android codebases is impractical.

2. **Performance**: Flutter compiles to native ARM code, unlike React Native which uses a JavaScript bridge. For financial apps where smooth scrolling through lists of assets is critical, this matters.

3. **UI Consistency**: Flutter draws every pixel itself using Skia engine, ensuring identical UI across platforms. Financial data displays need pixel-perfect consistency.

4. **Developer Productivity**: Hot reload allows instant UI changes without losing state - critical when designing complex forms like the Add Asset screen.

5. **Growing Ecosystem**: Dart/Flutter ecosystem has mature packages for everything we need (Hive, Riverpod, charts).

### Alternatives Considered

| Alternative | Why Not Chosen |
|-------------|----------------|
| **React Native** | JS bridge creates performance overhead. List scrolling (assets list) would be slower. Also, UI differences between iOS/Android. |
| **Native (Swift/Kotlin)** | Would need to maintain two codebases. As a solo developer project, this doubles the work. |
| **Kotlin Multiplatform** | Still maturing for UI. Compose Multiplatform is newer and less ecosystem support. |
| **Web App (PWA)** | Limited access to device features like biometrics, file system for exports. Mobile-first users expect native feel. |

### Tradeoffs Accepted

| Tradeoff | Impact | Mitigation |
|----------|--------|------------|
| Larger app size (~15-20MB vs ~5MB native) | Minor impact on downloads | Use `--split-debug-info` and `--obfuscate` in release builds |
| Platform-specific bugs | Occasional platform differences | Test on both iOS and Android simulators |
| Dart learning curve | Team familiarity | Dart is similar to Java/JavaScript, easy to learn |

---

## State Management: Riverpod

### Why Riverpod?

**Decision:** Use Riverpod instead of Provider, Bloc, GetX, or Redux.

**Reasoning:**

1. **Compile-time Safety**: Riverpod catches errors at compile time. Provider uses string-based lookups that can fail at runtime.

2. **No BuildContext Required**: Can access state from anywhere (repositories, services) without needing a widget's BuildContext. Essential for background data operations.

3. **Better Testing**: Providers can be easily overridden in tests without complex setup.

4. **Auto-disposal**: Providers automatically clean up when no longer listened to. Important for memory management with portfolio data.

5. **Future-proof**: Riverpod 2.x is the evolution of Provider (same author). It's where the ecosystem is heading.

### Alternatives Considered

| Alternative | Why Not Chosen |
|-------------|----------------|
| **Provider** | Predecessor to Riverpod, lacks compile-time safety. No access outside widget tree. |
| **Bloc** | Excellent but verbose. For MVP, Bloc's boilerplate (events, states, blocs) slows development. Better for larger teams. |
| **GetX** | All-in-one solution but "magic" behavior makes debugging harder. Poor testability. |
| **Redux** | Too much boilerplate for a mobile app. Better suited for complex web apps. |
| **MobX** | Good but smaller community in Flutter. Code generation required. |

### Riverpod Implementation Details

```dart
// Provider for repository (singleton)
final assetRepositoryProvider = Provider<AssetRepository>((ref) {
  return AssetRepository();
});

// FutureProvider for async data
final portfolioSummaryProvider = FutureProvider<PortfolioSummary>((ref) async {
  final repository = ref.watch(assetRepositoryProvider);
  // ... compute summary
  return summary;
});
```

**Why this pattern?**
- `Provider` for synchronous, non-changing values (repositories)
- `FutureProvider` for async operations (database reads)
- `ref.watch()` creates reactive dependency - UI rebuilds when data changes
- `ref.invalidate()` forces refresh (used after add/edit asset)

### Tradeoffs Accepted

| Tradeoff | Impact | Mitigation |
|----------|--------|------------|
| Learning curve | New syntax for developers | Excellent documentation, consistent patterns |
| Code generation (optional) | Additional build step | Used sparingly, manual providers mostly |
| Breaking changes between versions | Migration effort | Locked to stable 2.x version |

---

## Local Database: Hive

### Why Hive?

**Decision:** Use Hive instead of SQLite, ObjectBox, or shared_preferences.

**Reasoning:**

1. **No Native Dependencies**: Pure Dart, no platform-specific code needed. Simplifies builds and testing.

2. **Speed**: Hive is extremely fast for mobile. Benchmarks show 2-3x faster than SQLite for simple operations.

3. **Simple API**: No SQL queries, just Dart objects. Perfect for a portfolio app where queries are simple (get all assets, filter by type).

4. **Offline-first**: Works entirely on device, no network required.

5. **TypeAdapter System**: Strongly typed with code generation. `Asset` and `Transaction` models are type-safe.

### Alternatives Considered

| Alternative | Why Not Chosen |
|-------------|----------------|
| **SQLite (sqflite/drift)** | Overkill for our needs. No complex joins required. SQL syntax adds complexity. |
| **ObjectBox** | Commercial licensing concerns. Hive is MIT licensed. |
| **Isar** | Same author as Hive, newer but less mature ecosystem. |
| **shared_preferences** | Only for simple key-value pairs. Can't store complex Asset objects. |
| **Firebase Firestore** | Requires internet, creates privacy concerns with cloud storage. |

### Hive Implementation Details

**Type Registration:**
```dart
// main.dart
Hive.registerAdapter(AssetTypeAdapter());   // typeId: 0
Hive.registerAdapter(TransactionTypeAdapter()); // typeId: 1
Hive.registerAdapter(AssetAdapter());       // typeId: 2
Hive.registerAdapter(TransactionAdapter()); // typeId: 3
```

**Why typeIds?**
- Hive uses integer IDs for efficient serialization
- Must never change once deployed (breaks existing user data)
- Planned sequentially: enums first (0,1), then models (2,3)

**Box Structure:**
```dart
await Hive.openBox<Asset>('assets_box');
await Hive.openBox<Transaction>('transactions_box');
await Hive.openBox('settings_box');  // Dynamic for settings
```

**Why separate boxes?**
- Logical separation of data types
- Can clear assets without affecting settings
- Better for future encryption (encrypt financial data, not settings)

### Tradeoffs Accepted

| Tradeoff | Impact | Mitigation |
|----------|--------|------------|
| No relations | Can't do SQL JOINs | Store `assetId` in Transaction, query manually |
| Limited querying | No WHERE clauses | Filter in Dart code, acceptable for <1000 assets |
| Schema migrations | Manual version handling | Keep models backwards compatible |
| Code generation required | Build step needed | `build_runner` integrated into dev workflow |

---

## Architecture Pattern

### Feature-First Architecture

**Decision:** Use feature-first folder structure instead of layer-first.

**Structure:**
```
lib/
├── core/           # Shared utilities, theme, constants
├── data/           # Models, repositories (global)
├── features/       # Feature modules
│   ├── dashboard/
│   ├── assets/
│   ├── transactions/
│   └── settings/
└── shared/         # Shared widgets, providers
```

**Why Feature-First?**

1. **Scalability**: Each feature is self-contained. Adding "Goals" feature = new folder, no touching existing code.

2. **Team Collaboration**: Multiple developers can work on different features without merge conflicts.

3. **Code Discovery**: Looking for dashboard code? It's in `features/dashboard/`. Intuitive navigation.

4. **Lazy Loading**: Features can be lazily loaded (future optimization).

### Alternatives Considered

| Alternative | Why Not Chosen |
|-------------|----------------|
| **Layer-first** (`screens/`, `widgets/`, `models/`) | Doesn't scale. 20 screens in one folder becomes chaos. |
| **Clean Architecture** | Too complex for MVP. Separate domain/data/presentation layers = more files. |
| **MVC/MVVM** | Flutter widgets don't fit traditional MVC. Riverpod replaces ViewModels. |

### Why `core/`, `data/`, `shared/` are separate?

- **core/**: True app-wide utilities (theme, colors, constants). Rarely changes.
- **data/**: Models used across features. `Asset` is used in dashboard, assets, settings.
- **shared/**: Reusable UI components (`PortfolioSummaryCard` used in dashboard).

---

## UI/UX Decisions

### Dark-First Design

**Decision:** Dark theme as default and only theme (Phase 1).

**Reasoning:**

1. **User Preference**: Finance apps are often checked at night. Dark theme reduces eye strain.

2. **OLED Battery**: Dark themes use less battery on OLED screens (black pixels are off).

3. **Development Speed**: One theme = half the UI testing.

4. **Modern Aesthetic**: Dark themes feel premium, appropriate for finance.

**Color Palette:**
```dart
static const Color background = Color(0xFF0D0D0D);  // Near black
static const Color surface = Color(0xFF1E1E1E);     // Card backgrounds
static const Color primary = Color(0xFF6C63FF);     // Purple accent
static const Color success = Color(0xFF00C853);     // Profit
static const Color error = Color(0xFFFF5252);       // Loss
```

**Why these colors?**
- `0xFF0D0D0D` vs pure black: Easier on eyes, allows subtle shadows
- Purple primary: Unique (not typical finance blue), modern feel
- Green/Red for profit/loss: Universal financial convention

### Material 3 with Custom Theme

**Decision:** Use Material 3 (`useMaterial3: true`) with extensive customization.

**Why Material 3?**
- Modern widget designs (rounded corners, dynamic colors)
- Better accessibility defaults
- Future-proof (Google's direction)

**Why extensive customization?**
- Material defaults are "Google-ish", needed unique KashU identity
- Custom `CardTheme`, `InputDecorationTheme`, `ButtonTheme`

### No Custom Fonts (Phase 1)

**Decision:** Use system fonts instead of custom fonts like Inter.

**Reasoning:**
- Faster load times (no font files to bundle)
- System fonts are optimized per platform
- Can add custom fonts in Phase 2 for branding

---

## Data Models Design

### Asset Model

```dart
class Asset extends HiveObject {
  final String id;           // UUID
  String name;               // "Reliance Industries"
  String? symbol;            // "RELIANCE" (optional)
  AssetType type;            // Enum: stock, gold, crypto, etc.
  double quantity;           // 10.5 shares
  double purchasePrice;      // Per unit price at buy
  double currentPrice;       // Current per unit price
  String currency;           // "INR", "USD"
  DateTime purchaseDate;
  String? platform;          // "Zerodha"
  String? notes;
  DateTime createdAt;
  DateTime updatedAt;
  DateTime? priceUpdatedAt;
}
```

**Design Decisions:**

1. **UUID for ID**: Not auto-increment. UUIDs allow offline creation without ID conflicts.

2. **`HiveObject` extension**: Enables `asset.save()` for in-place updates without repository.

3. **Separate `purchasePrice` and `currentPrice`**: Allows gain/loss calculation without storing history.

4. **`currency` as String**: Not enum, allows adding currencies without code changes.

5. **Nullable `platform`**: User might not know/care where asset is held.

6. **Three timestamps**: `createdAt` (never changes), `updatedAt` (any edit), `priceUpdatedAt` (price specifically).

**Computed Properties:**
```dart
double get totalInvested => quantity * purchasePrice;
double get currentValue => quantity * currentPrice;
double get gainLoss => currentValue - totalInvested;
double get gainLossPercentage => (gainLoss / totalInvested) * 100;
```

**Why computed vs stored?**
- Always accurate (no sync issues)
- Storage space saved
- Single source of truth (`quantity`, `purchasePrice`, `currentPrice`)

### AssetType Enum

```dart
enum AssetType {
  stock, mutualFund, gold, crypto, bond, fixedDeposit, cash, realEstate
}
```

**Why Enum with Extensions?**

```dart
extension AssetTypeExtension on AssetType {
  String get displayName { ... }
  IconData get icon { ... }
  Color get color { ... }
  String get unitLabel { ... }
}
```

- **Type safety**: Can't have invalid asset type
- **Single source**: Display name, icon, color defined once
- **Hive compatibility**: Enums serialize as integers (efficient)

### Transaction Model

```dart
class Transaction extends HiveObject {
  final String id;
  final String assetId;      // Links to Asset
  TransactionType type;      // buy, sell, dividend, interest
  double quantity;
  double price;
  double amount;             // quantity * price (stored for efficiency)
  String currency;
  DateTime date;
  String? notes;
  DateTime createdAt;
}
```

**Why store `amount` if it's computable?**
- Historical accuracy: If user edits Asset, Transaction should reflect original
- Performance: Common query is "total transactions amount"

---

## Security Considerations

### Phase 1 Security Posture

**Current State:**
- Data stored in Hive (unencrypted by default)
- No authentication required
- Export creates plain JSON

**Why no encryption in Phase 1?**
1. MVP priority was functionality, not security hardening
2. Hive encryption adds complexity (key management)
3. User's device-level security (PIN/biometric) provides first layer

### Planned Phase 2 Security

1. **Hive Box Encryption:**
   ```dart
   var key = await secureStorage.read(key: 'hive_key');
   if (key == null) {
     key = base64Url.encode(Hive.generateSecureKey());
     await secureStorage.write(key: 'hive_key', value: key);
   }
   await Hive.openBox('assets', encryptionCipher: HiveAesCipher(base64Url.decode(key)));
   ```

2. **App Lock:**
   - PIN entry on app open
   - Biometric (Face ID, fingerprint) via `local_auth`

3. **Encrypted Export:**
   - Password-protect JSON backups

### Security Tradeoffs

| Risk | Mitigation |
|------|------------|
| Data theft if device stolen | Phase 2: Hive encryption + app lock |
| Shoulder surfing | Phase 2: Masked amounts toggle |
| Export file stolen | Phase 2: Encrypted exports |
| Screenshot/screen recording | Phase 2: FLAG_SECURE on Android |

---

## Challenges & Mitigations

### Challenge 1: Hive Code Generation Errors

**Problem:** `build_runner` failed with cryptic errors about missing `.g.dart` files.

**Root Cause:** The default `main.dart` from `flutter create` had syntax errors that blocked code generation.

**Solution:**
1. Fixed `main.dart` first (removed broken default code)
2. Ran `dart run build_runner clean` to clear cache
3. Re-ran `dart run build_runner build --delete-conflicting-outputs`

**Prevention:** Always ensure valid Dart files before running code generation.

### Challenge 2: Analyzer Version Mismatch

**Problem:** Warning about `analyzer` version not supporting SDK version.

**Root Cause:** `riverpod_generator` and `hive_generator` depend on older `analyzer` versions.

**Solution:** Accepted warning (not error). All functionality works. Can upgrade when dependencies update.

**Lesson:** Lock major dependency versions in `pubspec.yaml` to avoid breaking changes.

### Challenge 3: Extension Methods Not Found

**Problem:** `asset.type.color` failed with "getter not defined".

**Root Cause:** Extension methods in `asset_type.dart` require explicit import.

**Solution:** Added `import '../../data/models/asset_type.dart';` to files using extensions.

**Lesson:** Dart extensions aren't automatically available - must import defining file.

### Challenge 4: BuildContext Across Async Gaps

**Problem:** Linter warned about using `context` after `await` calls.

**Root Cause:** Widget might be disposed during async operation, making context invalid.

**Solution:**
```dart
// Before (dangerous)
await repository.addAsset(asset);
Navigator.pop(context);  // Context might be invalid!

// After (safe)
await repository.addAsset(asset);
if (mounted) {  // Check if widget still exists
  Navigator.pop(context);
}
```

### Challenge 5: INR Currency Formatting

**Problem:** Standard number formatting doesn't support Indian notation (lakhs, crores).

**Root Cause:** `intl` package's `NumberFormat.currency()` doesn't have Indian grouping.

**Solution:** Custom formatter:
```dart
static String formatCompactINR(double amount) {
  if (amount >= 10000000) {
    return '₹${(amount / 10000000).toStringAsFixed(2)}Cr';
  } else if (amount >= 100000) {
    return '₹${(amount / 100000).toStringAsFixed(2)}L';
  }
  // ...
}
```

---

## Performance Considerations

### Startup Performance

**Optimizations:**
1. Hive boxes opened once in `main()`, stored globally
2. No network calls at startup (offline-first)
3. Lazy loading of screens via `IndexedStack`

**Measured Impact:** Cold start ~2 seconds on mid-range device (acceptable).

### List Performance

**Optimizations:**
1. `ListView.builder` for lazy item construction
2. `ListView.separated` to avoid rebuilding dividers
3. Keys on list items for efficient diffing

**Tradeoff:** Without pagination, 1000+ assets might slow scrolldown. Acceptable for personal use (most users have <100 assets).

### Memory Management

**Optimizations:**
1. `FutureProvider` with auto-disposal when not watched
2. Controllers (`TextEditingController`) disposed in `dispose()`
3. No global variables holding large data

---

## Future Scalability

### Adding New Asset Types

**Current Design:**
```dart
enum AssetType { stock, mutualFund, gold, crypto, bond, fixedDeposit, cash, realEstate }
```

**To add "Commodities":**
1. Add `commodities` to enum
2. Add to `AssetTypeExtension` (displayName, icon, color)
3. No database migration needed (Hive stores enum as int, new value = new int)

### Adding New Features

**Adding "Goals" feature:**
1. Create `lib/features/goals/`
2. Create `Goal` model with Hive annotations
3. Register adapter in `main.dart`
4. Add navigation entry

**No changes to existing code required** - feature-first architecture benefit.

### Multi-Device Sync (Future)

**Current:** Single device, Hive local storage.

**Future Options:**
1. **Self-hosted sync:** User runs their own server
2. **End-to-end encrypted cloud:** Encrypt locally, store encrypted blob in cloud
3. **P2P sync:** Device-to-device via Bluetooth/WiFi

**Why not Firebase now?** Privacy requirement - user data shouldn't touch third-party servers.

---

## Dependencies Analysis

### Production Dependencies

| Package | Purpose | Risk Level | Update Strategy |
|---------|---------|------------|-----------------|
| flutter_riverpod | State management | Low | Follow major versions |
| hive_flutter | Local database | Low | Stable, rarely updated |
| fl_chart | Charts | Medium | Lock version, visual changes |
| local_auth | Biometrics | Low | Platform-maintained |
| flutter_secure_storage | Encrypted storage | Low | Security critical, update promptly |
| intl | Internationalization | Low | Flutter team maintained |
| uuid | ID generation | Very Low | Stable, no changes expected |
| path_provider | File paths | Low | Flutter team maintained |
| share_plus | Sharing | Low | Federated plugin, stable |

### Development Dependencies

| Package | Purpose | Risk Level |
|---------|---------|------------|
| hive_generator | Code gen | Low |
| build_runner | Code gen | Low |
| riverpod_generator | Code gen | Low |
| flutter_lints | Linting | Very Low |

### Dependency Security

- All packages from pub.dev (official Dart repository)
- Checked for recent updates (active maintenance)
- No packages with known vulnerabilities
- Locked to specific versions in `pubspec.lock`

---

## Testing Strategy

### Phase 1 Testing (MVP)

**Unit Tests:**
- Model tests (Asset calculations)
- Repository tests (CRUD operations)

**Widget Tests:**
- Basic smoke test (app loads)

**Manual Testing:**
- All user flows on iOS and Android simulators

### Phase 2 Testing (Planned)

**Integration Tests:**
- Full user journeys (add asset → view dashboard → export)

**Golden Tests:**
- Screenshot comparisons for UI regression

**Performance Tests:**
- Large dataset (1000 assets) scroll performance

---

## Key Learnings

### What Worked Well

1. **Riverpod** - Clean state management, easy to test, great DX
2. **Hive** - Fast, simple API, perfect for offline-first
3. **Feature-first architecture** - Easy to navigate, scales well
4. **Dark theme only** - Reduced design decisions, faster development

### What Could Be Improved

1. **More test coverage** - MVP prioritized features over tests
2. **Better error handling** - Some try/catch could be more granular
3. **Accessibility** - Need to audit for screen readers
4. **Code documentation** - More inline comments for complex logic

### Recommendations for Phase 2

1. Add widget tests for each screen
2. Implement Hive encryption before adding more sensitive data
3. Add crashlytics/analytics (privacy-respecting)
4. Performance profiling with Flutter DevTools
5. Accessibility audit with TalkBack/VoiceOver

---

## Appendix: Quick Reference

### Running the Project

```bash
# Install dependencies
flutter pub get

# Generate Hive adapters
dart run build_runner build --delete-conflicting-outputs

# Run on device/emulator
flutter run

# Build release APK
flutter build apk --release

# Build release iOS
flutter build ios --release
```

### Common Commands

```bash
# Analyze code
flutter analyze

# Run tests
flutter test

# Clean build
flutter clean && flutter pub get

# Regenerate Hive adapters
dart run build_runner clean
dart run build_runner build --delete-conflicting-outputs
```

### Key Files Reference

| File | Purpose |
|------|---------|
| `lib/main.dart` | App entry, Hive init |
| `lib/core/theme/app_theme.dart` | All theme definitions |
| `lib/data/models/asset.dart` | Asset model |
| `lib/data/repositories/asset_repository.dart` | Data access |
| `lib/shared/providers/portfolio_provider.dart` | Riverpod providers |
| `lib/features/dashboard/dashboard_screen.dart` | Main dashboard |

---

*Document Version: 1.0*
*Last Updated: February 2026*
*Author: KashU Development Team*
