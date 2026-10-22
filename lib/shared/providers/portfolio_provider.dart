import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../../core/constants/app_constants.dart';
import '../../data/models/asset.dart';
import '../../data/models/asset_type.dart';
import '../../data/models/portfolio_summary.dart';
import '../../data/repositories/asset_repository.dart';
import '../../data/repositories/portfolio_write_service.dart';
import '../../data/repositories/transaction_repository.dart';
import '../../services/auth_service.dart';
import '../../services/base_currency_converter.dart';
import '../../services/currency_converter_service.dart';
import '../../services/gold_price_service.dart';
import '../../services/price_history_service.dart';
import '../../services/price_update_service.dart';

/// Provider for AssetRepository
final assetRepositoryProvider = Provider<AssetRepository>((ref) {
  return AssetRepository();
});

/// Provider for TransactionRepository
final transactionRepositoryProvider = Provider<TransactionRepository>((ref) {
  return TransactionRepository();
});

/// Provider for AuthService (biometric / device-credential auth)
final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService();
});

/// Whether the app is currently locked behind biometric/PIN authentication.
///
/// Seeded at startup (true when app lock is enabled) via a ProviderScope
/// override in main.dart, set true again by the resume re-lock in KashUApp,
/// and cleared by LockScreen on successful authentication. The lock renders
/// as an overlay above the whole app — no navigation involved.
final appLockedProvider = StateProvider<bool>((ref) => false);

/// Provider for PortfolioWriteService — combined asset+transaction writes
final portfolioWriteServiceProvider = Provider<PortfolioWriteService>((ref) {
  return PortfolioWriteService(
    assetRepository: ref.watch(assetRepositoryProvider),
    transactionRepository: ref.watch(transactionRepositoryProvider),
  );
});

/// Provider for base currency (persisted in settings)
final baseCurrencyProvider = StateProvider<String>((ref) {
  final repo = ref.watch(assetRepositoryProvider);
  return repo.getBaseCurrency();
});

/// Provider for portfolio summary.
///
/// All money is converted into the user's base currency before aggregating,
/// so a portfolio holding assets in different currencies sums correctly (the
/// old code added raw values across currencies). Per-asset gain/loss *percent*
/// is currency-independent, so gainers/losers are unaffected.
final portfolioSummaryProvider = FutureProvider<PortfolioSummary>((ref) async {
  final repository = ref.watch(assetRepositoryProvider);
  final base = ref.watch(baseCurrencyProvider);

  final assets = repository.getAllAssets();
  if (assets.isEmpty) {
    return PortfolioSummary.empty();
  }

  // Offline-first: the forex network is only touched when a holding is
  // actually in a different currency than the base. The rebalancing screen
  // reads this summary and the capital-gains PDF builds the same converter,
  // so all three total a mixed-currency portfolio identically.
  final fx = await BaseCurrencyConverter.forAssets(
    assets,
    base: base,
    loadRates: () => ref.watch(exchangeRatesProvider.future),
  );

  double totalValue = 0;
  double totalInvested = 0;
  final allocation = <AssetType, double>{};
  for (final a in assets) {
    final value = fx.valueOf(a);
    totalValue += value;
    totalInvested += fx.investedOf(a);
    allocation.update(a.type, (v) => v + value, ifAbsent: () => value);
  }

  // Before the first price refresh, values are 0 — fall back to invested so
  // the allocation chart isn't blank (mirrors AssetRepository.getAssetAllocation).
  if (totalValue == 0 && totalInvested > 0) {
    allocation.clear();
    for (final a in assets) {
      final inv = fx.investedOf(a);
      allocation.update(a.type, (v) => v + inv, ifAbsent: () => inv);
    }
  }

  final totalGainLoss = totalValue - totalInvested;
  final totalGainLossPercentage =
      totalInvested > 0 ? (totalGainLoss / totalInvested) * 100 : 0.0;

  // Today's change: sum of PER-ASSET value deltas (now vs the most recent
  // prior-day snapshot), for assets present in both, converted to base with
  // current rates. Per-asset (not total-vs-total) so buying/selling an asset
  // doesn't masquerade as a price move, and so a base-currency switch can't
  // corrupt the comparison. Shown only once such a baseline exists.
  //
  // A sale (or a quantity edit) since the snapshot changes an asset's value
  // without any price moving, so where the snapshot recorded the quantity
  // the baseline is rescaled to today's: prior price x units held now.
  final priorSnapshot =
      ref.watch(priceHistoryServiceProvider).previousDaySnapshot();
  double todaysChange = 0;
  double priorBaseline = 0;
  var hasTodaysChange = false;
  if (priorSnapshot != null) {
    for (final a in assets) {
      final priorValue = priorSnapshot.assetValues[a.id];
      if (priorValue == null) continue; // no baseline (asset is new)
      final priorQty = priorSnapshot.assetQuantities[a.id];
      if (priorQty != null && priorQty <= 0 && a.quantity > 0) {
        continue; // held nothing then: no prior price to compare against
      }
      final priorNative = priorQty != null && priorQty > 0
          ? priorValue / priorQty * a.quantity
          : priorValue;
      hasTodaysChange = true;
      final priorBase = fx.convert(priorNative, a.currency);
      final nowBase = fx.valueOf(a);
      todaysChange += nowBase - priorBase;
      priorBaseline += priorBase;
    }
  }
  if (!hasTodaysChange) todaysChange = 0;
  final todaysChangePercentage = (hasTodaysChange && priorBaseline > 0)
      ? (todaysChange / priorBaseline) * 100
      : 0.0;

  return PortfolioSummary(
    totalValue: totalValue,
    totalInvested: totalInvested,
    totalGainLoss: totalGainLoss,
    totalGainLossPercentage: totalGainLossPercentage,
    todaysChange: todaysChange,
    todaysChangePercentage: todaysChangePercentage,
    hasTodaysChange: hasTodaysChange,
    assetAllocation: allocation,
    topGainers: repository.getTopGainers(),
    topLosers: repository.getTopLosers(),
    // Open positions: a fully sold holding stays stored (quantity 0) for its
    // history and cost basis, but is no longer something the user holds.
    totalAssets: assets.where((a) => a.quantity > 0).length,
    lastUpdated: DateTime.now(),
  );
});

/// Provider for all assets - correctly typed as `List<Asset>`
final allAssetsProvider = Provider<List<Asset>>((ref) {
  final repository = ref.watch(assetRepositoryProvider);
  return repository.getAllAssets();
});

/// The current stored copy of one asset, or null once it has been deleted.
///
/// AssetRepository writes a *new* object on every update, so a screen that
/// holds on to the [Asset] it was opened with keeps showing (and saving) stale
/// figures. Screens showing a single asset watch this instead; it follows
/// [allAssetsProvider], which every write path invalidates.
final assetByIdProvider = Provider.family<Asset?, String>((ref, id) {
  return ref
      .watch(allAssetsProvider)
      .firstWhereOrNull((asset) => asset.id == id);
});

/// Provider for CurrencyConverterService (singleton with cache)
final currencyConverterServiceProvider =
    Provider<CurrencyConverterService>((ref) {
  return CurrencyConverterService();
});

/// Live USD-based exchange rates, used to convert holdings into the base
/// currency for display. The service caches for 30 min, so watchers resolve
/// quickly after the first load; display code falls back to approximate
/// static rates via [ExchangeRateResult.convertBetween] while this is loading.
final exchangeRatesProvider = FutureProvider<ExchangeRateResult>((ref) async {
  return ref.watch(currencyConverterServiceProvider).fetchRates();
});

/// Provider for PriceHistoryService (daily snapshots → today's change + sparkline)
final priceHistoryServiceProvider = Provider<PriceHistoryService>((ref) {
  return PriceHistoryService();
});

/// Provider for GoldPriceService (uses COMEX GC=F + live forex + Indian taxes)
final goldPriceServiceProvider = Provider<GoldPriceService>((ref) {
  final currencyConverter = ref.watch(currencyConverterServiceProvider);
  return GoldPriceService(currencyConverter: currencyConverter);
});

/// Provider for PriceUpdateService (includes currency conversion + gold tax)
final priceUpdateServiceProvider = Provider<PriceUpdateService>((ref) {
  final assetRepo = ref.watch(assetRepositoryProvider);
  final currencyConverter = ref.watch(currencyConverterServiceProvider);
  final goldPriceService = ref.watch(goldPriceServiceProvider);
  return PriceUpdateService(
    assetRepository: assetRepo,
    currencyConverter: currencyConverter,
    goldPriceService: goldPriceService,
  );
});

/// Tracks whether a price refresh is currently in progress
final isRefreshingPricesProvider = StateProvider<bool>((ref) => false);

/// Holds the result of the last price refresh (null if never refreshed)
final lastRefreshResultProvider =
    StateProvider<PriceRefreshResult?>((ref) => null);

/// Threshold after which prices are considered stale and a warning is shown.
const Duration stalePriceThreshold = Duration(hours: 4);

/// True when prices haven't been refreshed for [stalePriceThreshold] or longer.
///
/// Reads the persisted last-refresh timestamp from the settings box so the
/// warning survives app restarts.
final isPriceStaleProvider = Provider<bool>((ref) {
  // Also invalidated after a fresh refresh so the banner clears immediately.
  final lastResult = ref.watch(lastRefreshResultProvider);
  if (lastResult != null) {
    return DateTime.now().difference(lastResult.completedAt) >
        stalePriceThreshold;
  }

  final settings = Hive.box(AppConstants.settingsBox);
  final raw = settings.get('lastPriceRefreshAt') as String?;
  if (raw == null) return false; // no history → don't nag on first open
  final savedAt = DateTime.tryParse(raw);
  if (savedAt == null) return false;
  return DateTime.now().difference(savedAt) > stalePriceThreshold;
});

/// How long without a backup before the dashboard nudges the user — also the
/// snooze window after the nudge is dismissed.
const Duration backupNudgePeriod = Duration(days: 30);

/// True when the user has assets but hasn't exported a backup within
/// [backupNudgePeriod] (or ever), and hasn't dismissed the nudge within the
/// same window.
///
/// Reads timestamps from the settings box — invalidate this provider after
/// writing an export or a dismissal so the banner updates immediately.
final isBackupOverdueProvider = Provider<bool>((ref) {
  final assets = ref.watch(allAssetsProvider);
  if (assets.isEmpty) return false; // nothing to lose yet — don't nag

  final settings = Hive.box(AppConstants.settingsBox);
  DateTime? readTime(String key) {
    final raw = settings.get(key) as String?;
    return raw == null ? null : DateTime.tryParse(raw);
  }

  final dismissedAt = readTime(AppConstants.keyBackupNudgeDismissedAt);
  if (dismissedAt != null &&
      DateTime.now().difference(dismissedAt) < backupNudgePeriod) {
    return false; // snoozed
  }

  final lastExportAt = readTime(AppConstants.keyLastExportAt);
  return lastExportAt == null ||
      DateTime.now().difference(lastExportAt) > backupNudgePeriod;
});
