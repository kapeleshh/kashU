import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants/app_constants.dart';
import '../../core/utils/transaction_validator.dart';
import '../models/asset.dart';
import '../models/transaction.dart';
import '../models/transaction_type.dart';
import 'asset_repository.dart';
import 'transaction_repository.dart';

/// Coordinates writes that span both the assets and transactions boxes.
///
/// Hive has no cross-box transactions, so a crash between the two halves of
/// a combined write can leave the boxes inconsistent. This service keeps them
/// consistent with compensation (for adds) and pending-write markers that
/// [completeInterruptedWrites] finishes on the next launch (for deletes and
/// Clear All Data).
///
/// Only marked writes are ever cleaned up. Transactions whose asset is
/// missing for any *other* reason — the pre-tombstone delete path kept them,
/// and imported backups may legitimately contain them — are real user history
/// (they feed the Activity screen and the tax exports) and are never touched.
class PortfolioWriteService {
  final AssetRepository _assetRepository;
  final TransactionRepository _transactionRepository;
  final Box? _settingsBoxOverride;

  PortfolioWriteService({
    AssetRepository? assetRepository,
    TransactionRepository? transactionRepository,
    Box? settingsBox,
  })  : _assetRepository = assetRepository ?? AssetRepository(),
        _transactionRepository =
            transactionRepository ?? TransactionRepository(),
        _settingsBoxOverride = settingsBox;

  Box get _settings =>
      _settingsBoxOverride ?? Hive.box(AppConstants.settingsBox);

  /// Asset ids whose delete was started but not yet confirmed complete.
  List<String> _pendingDeletes() {
    final raw = _settings.get(AppConstants.keyPendingAssetDeletes);
    if (raw is! List) return <String>[];
    return raw.whereType<String>().toList();
  }

  Future<void> _addPendingDelete(String assetId) async {
    final pending = _pendingDeletes();
    if (!pending.contains(assetId)) {
      await _settings
          .put(AppConstants.keyPendingAssetDeletes, [...pending, assetId]);
    }
  }

  Future<void> _removePendingDelete(String assetId) async {
    final pending = _pendingDeletes()..remove(assetId);
    await _settings.put(AppConstants.keyPendingAssetDeletes, pending);
  }

  /// Add [asset] and log its initial BUY transaction as one logical write.
  ///
  /// If logging the transaction throws, the just-added asset is removed
  /// again (compensation) and the error is rethrown so the caller can
  /// surface it — no asset is left behind without its purchase record.
  Future<void> addAssetWithBuyTransaction(Asset asset) async {
    await _assetRepository.addAsset(asset);
    try {
      await _transactionRepository.logBuyTransaction(asset);
    } catch (_) {
      await _assetRepository.deleteAsset(asset.id);
      rethrow;
    }
  }

  /// Delete an asset and all of its transactions.
  ///
  /// The asset id is tombstoned in the settings box before anything is
  /// deleted, and the tombstone is cleared only once both halves succeeded.
  /// A failure in between is finished by [completeInterruptedWrites] on the
  /// next launch, so the user's delete neither leaks half-deleted history
  /// nor silently reverts.
  ///
  /// If the asset delete itself throws, nothing has been deleted yet — the
  /// tombstone is removed again and the error rethrown, so the caller sees
  /// a failed delete instead of the app completing it unannounced later.
  Future<void> deleteAssetWithTransactions(String assetId) async {
    await _addPendingDelete(assetId);
    try {
      await _assetRepository.deleteAsset(assetId);
    } catch (_) {
      await _removePendingDelete(assetId);
      rethrow;
    }
    try {
      await _transactionRepository.deleteTransactionsForAsset(assetId);
      await _removePendingDelete(assetId);
    } catch (e) {
      debugPrint('[KashU] Transaction cleanup for asset $assetId failed — '
          'the delete will be completed on the next launch: $e');
    }
  }

  /// Drop any delete tombstones for [assetIds].
  ///
  /// Call after a successful import: a backup that recreates a tombstoned
  /// asset id expresses the opposite intent to the interrupted delete and
  /// must win — otherwise the next launch would silently delete the freshly
  /// restored asset and its history.
  Future<void> removeTombstonesFor(Iterable<String> assetIds) async {
    final ids = assetIds.toSet();
    final pending = _pendingDeletes();
    final remaining = pending.where((id) => !ids.contains(id)).toList();
    if (remaining.length != pending.length) {
      await _settings.put(AppConstants.keyPendingAssetDeletes, remaining);
    }
  }

  /// Clear both boxes as one logical write (Settings → Clear All Data).
  ///
  /// Protected like single deletes: a pending-clear flag is set before the
  /// first clear and removed after the last, so a crash in between is
  /// finished by [completeInterruptedWrites] instead of leaving ghost
  /// history that the tax export would keep including. Transactions are
  /// cleared before assets so even an unmarked partial failure leaves an
  /// empty history, not an orphaned one. All delete tombstones are dropped
  /// too — after a full clear there is nothing left for them to clean up.
  Future<void> clearAllData() async {
    await _settings.put(AppConstants.keyPendingClearAll, true);
    await _transactionRepository.clearAll();
    await _assetRepository.clearAll();
    await _settings.put(AppConstants.keyPendingAssetDeletes, <String>[]);
    await _settings.put(AppConstants.keyPendingClearAll, false);
  }

  /// Finish combined writes that were interrupted mid-way.
  ///
  /// Runs once per launch (after migrations). An interrupted Clear All Data
  /// is finished first — it supersedes individual tombstones. Then each
  /// asset id tombstoned by [deleteAssetWithTransactions] is processed: its
  /// remaining transactions — and the asset itself, if the interruption
  /// happened before it was removed — are deleted, then the tombstone is
  /// cleared. Tombstones are cleared one by one as their cleanup succeeds,
  /// so a crash mid-loop never redoes finished work. Returns the number of
  /// transactions removed.
  Future<int> completeInterruptedWrites() async {
    if (_settings.get(AppConstants.keyPendingClearAll) == true) {
      final removed = _transactionRepository.totalTransactions;
      await clearAllData();
      debugPrint('[KashU] Completed an interrupted Clear All Data '
          '($removed transaction(s) removed)');
      return removed;
    }

    final pending = _pendingDeletes();
    if (pending.isEmpty) return 0;

    var removed = 0;
    for (final assetId in pending) {
      final leftovers =
          _transactionRepository.getTransactionsForAsset(assetId);
      if (leftovers.isNotEmpty) {
        await _transactionRepository.deleteTransactionsForAsset(assetId);
        removed += leftovers.length;
      }
      if (_assetRepository.getAssetById(assetId) != null) {
        await _assetRepository.deleteAsset(assetId);
      }
      await _removePendingDelete(assetId);
    }
    debugPrint('[KashU] Completed ${pending.length} interrupted delete(s), '
        'removed $removed transaction(s)');
    return removed;
  }

  // ─── Recording sells and income ───────────────────────────────────────────

  /// Record selling [quantity] units of [assetId] at [pricePerUnit] on
  /// [date], and lower the holding by [quantity] as one logical write.
  ///
  /// The SELL carries what ExportService's capital-gains rows read: the
  /// quantity, the per-unit price, the proceeds (quantity x price) in the
  /// holding's currency, and the trade date. The holding's average cost
  /// (purchasePrice) is left unchanged — it is the cost basis of the units
  /// still held as much as of the ones sold.
  ///
  /// Selling everything leaves the asset with quantity 0. It is kept, not
  /// deleted: the capital-gains report looks the sell's cost basis and
  /// purchase date up on the asset, and a deleted asset would drop the gain.
  ///
  /// The transaction is written first and removed again if lowering the
  /// quantity throws (compensation), so a failed sale leaves neither half.
  /// Throws [ArgumentError] for input the form would reject (see
  /// [TransactionValidator]) and [StateError] if the asset no longer exists.
  Future<Transaction> recordSell({
    required String assetId,
    required double quantity,
    required double pricePerUnit,
    required DateTime date,
    String? notes,
  }) async {
    final asset = _requireAsset(assetId);
    _check(TransactionValidator.sellQuantity(quantity, asset.quantity));
    _check(TransactionValidator.positive(pricePerUnit));
    _check(TransactionValidator.date(date, purchaseDate: asset.purchaseDate));

    final now = DateTime.now();
    final sell = Transaction(
      id: const Uuid().v4(),
      assetId: asset.id,
      type: TransactionType.sell,
      quantity: quantity,
      price: pricePerUnit,
      amount: quantity * pricePerUnit,
      currency: asset.currency,
      date: date,
      notes: _cleanNotes(notes),
      createdAt: now,
    );

    await _transactionRepository.addTransaction(sell);
    try {
      await _assetRepository.updateAsset(asset.copyWith(
        quantity:
            TransactionValidator.remainingAfterSell(asset.quantity, quantity),
        updatedAt: now,
      ));
    } catch (_) {
      await _transactionRepository.deleteTransaction(sell.id);
      rethrow;
    }
    return sell;
  }

  /// Record a dividend or interest payment of [amount], in the holding's
  /// currency, received on [date]. Only the transactions box is written:
  /// income does not change the holding.
  ///
  /// Throws [ArgumentError] for any other [type] or invalid input, and
  /// [StateError] if the asset no longer exists.
  Future<Transaction> recordIncome({
    required String assetId,
    required TransactionType type,
    required double amount,
    required DateTime date,
    String? notes,
  }) async {
    if (type != TransactionType.dividend && type != TransactionType.interest) {
      throw ArgumentError.value(type, 'type', 'Must be dividend or interest');
    }
    final asset = _requireAsset(assetId);
    _check(TransactionValidator.positive(amount));
    _check(TransactionValidator.date(date, purchaseDate: asset.purchaseDate));

    final income = Transaction(
      id: const Uuid().v4(),
      assetId: asset.id,
      type: type,
      quantity: 0,
      price: 0,
      amount: amount,
      currency: asset.currency,
      date: date,
      notes: _cleanNotes(notes),
      createdAt: DateTime.now(),
    );
    await _transactionRepository.addTransaction(income);
    return income;
  }

  /// Delete [transaction]. Deleting a SELL also returns its units to the
  /// holding (when the asset still exists), so undoing a mistaken sale
  /// restores the quantity it took away. Other types only remove the record.
  ///
  /// Compensated like [recordSell]: if restoring the quantity throws, the
  /// transaction is put back and the error rethrown.
  Future<void> deleteTransaction(Transaction transaction) async {
    final asset = transaction.type == TransactionType.sell
        ? _assetRepository.getAssetById(transaction.assetId)
        : null;

    await _transactionRepository.deleteTransaction(transaction.id);
    if (asset == null) return;
    try {
      await _assetRepository.updateAsset(asset.copyWith(
        quantity: asset.quantity + transaction.quantity,
        updatedAt: DateTime.now(),
      ));
    } catch (_) {
      // A fresh copy: the deleted HiveObject is detached from its box.
      await _transactionRepository.addTransaction(transaction.copyWith());
      rethrow;
    }
  }

  Asset _requireAsset(String assetId) {
    final asset = _assetRepository.getAssetById(assetId);
    if (asset == null) throw StateError('Asset $assetId no longer exists');
    return asset;
  }

  static void _check(String? error) {
    if (error != null) throw ArgumentError(error);
  }

  static String? _cleanNotes(String? notes) {
    final trimmed = notes?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}
