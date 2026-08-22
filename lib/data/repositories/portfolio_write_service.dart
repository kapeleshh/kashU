import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../core/constants/app_constants.dart';
import '../models/asset.dart';
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
}
