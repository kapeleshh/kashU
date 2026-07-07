import 'package:flutter/foundation.dart';

import '../models/asset.dart';
import 'asset_repository.dart';
import 'transaction_repository.dart';

/// Coordinates writes that span both the assets and transactions boxes.
///
/// Hive has no cross-box transactions, so a crash between the two halves of
/// a combined write can leave the boxes inconsistent. This service keeps them
/// consistent with compensation (for adds) and a startup sweep (for deletes).
class PortfolioWriteService {
  final AssetRepository _assetRepository;
  final TransactionRepository _transactionRepository;

  PortfolioWriteService({
    AssetRepository? assetRepository,
    TransactionRepository? transactionRepository,
  })  : _assetRepository = assetRepository ?? AssetRepository(),
        _transactionRepository =
            transactionRepository ?? TransactionRepository();

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
  /// The asset is deleted first; if transaction cleanup then fails, the
  /// leftovers are orphans that [sweepOrphanedTransactions] removes on the
  /// next launch, so the failure is logged rather than rethrown.
  Future<void> deleteAssetWithTransactions(String assetId) async {
    await _assetRepository.deleteAsset(assetId);
    try {
      await _transactionRepository.deleteTransactionsForAsset(assetId);
    } catch (e) {
      debugPrint('[KashU] Transaction cleanup for asset $assetId failed '
          '(the startup sweep will remove the leftovers): $e');
    }
  }

  /// Remove transactions whose asset no longer exists.
  ///
  /// Runs on every app launch (right after migrations) so interrupted
  /// deletes and pre-existing orphans get cleaned up. Returns the number of
  /// transactions removed.
  Future<int> sweepOrphanedTransactions() async {
    final liveAssetIds =
        _assetRepository.getAllAssets().map((a) => a.id).toSet();
    final removed =
        await _transactionRepository.deleteTransactionsNotIn(liveAssetIds);
    if (removed > 0) {
      debugPrint('[KashU] Swept $removed orphaned transaction(s)');
    }
    return removed;
  }
}
