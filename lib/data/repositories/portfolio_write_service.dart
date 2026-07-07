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
/// consistent with compensation (for adds) and delete tombstones that
/// [completeInterruptedDeletes] finishes on the next launch (for deletes).
///
/// Only tombstoned deletes are ever cleaned up. Transactions whose asset is
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
  /// A crash or failure at any point in between is finished by
  /// [completeInterruptedDeletes] on the next launch, so the user's delete
  /// neither leaks half-deleted history nor silently reverts.
  Future<void> deleteAssetWithTransactions(String assetId) async {
    await _addPendingDelete(assetId);
    await _assetRepository.deleteAsset(assetId);
    try {
      await _transactionRepository.deleteTransactionsForAsset(assetId);
      await _removePendingDelete(assetId);
    } catch (e) {
      debugPrint('[KashU] Transaction cleanup for asset $assetId failed — '
          'the delete will be completed on the next launch: $e');
    }
  }

  /// Finish asset deletes that were interrupted mid-write.
  ///
  /// Runs once per launch (after migrations). Only asset ids tombstoned by
  /// [deleteAssetWithTransactions] are processed: their remaining
  /// transactions — and the asset itself, if the interruption happened
  /// before it was removed — are deleted, then the tombstone is cleared.
  /// Each tombstone is cleared as soon as its cleanup succeeds, so a crash
  /// mid-loop never redoes finished work. Returns the number of
  /// transactions removed.
  Future<int> completeInterruptedDeletes() async {
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
