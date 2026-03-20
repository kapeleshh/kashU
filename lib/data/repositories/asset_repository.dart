import 'package:hive_flutter/hive_flutter.dart';
import '../models/asset.dart';
import '../models/asset_type.dart';
import '../../core/constants/app_constants.dart';

// Settings box helpers
Box _settingsBox() => Hive.box(AppConstants.settingsBox);

/// Repository for managing Asset data in Hive
class AssetRepository {
  Box<Asset>? _box;

  Box<Asset> get box {
    _box ??= Hive.box<Asset>(AppConstants.assetsBox);
    return _box!;
  }

  /// Get all assets
  List<Asset> getAllAssets() {
    return box.values.toList();
  }

  /// Get asset by ID
  Asset? getAssetById(String id) {
    try {
      return box.values.firstWhere((asset) => asset.id == id);
    } catch (e) {
      return null;
    }
  }

  /// Get assets by type
  List<Asset> getAssetsByType(AssetType type) {
    return box.values.where((asset) => asset.type == type).toList();
  }

  /// Get assets by platform
  List<Asset> getAssetsByPlatform(String platform) {
    return box.values.where((asset) => asset.platform == platform).toList();
  }

  /// Add a new asset
  Future<void> addAsset(Asset asset) async {
    await box.put(asset.id, asset);
  }

  /// Update an existing asset
  Future<void> updateAsset(Asset asset) async {
    await box.put(asset.id, asset);
  }

  /// Delete an asset
  Future<void> deleteAsset(String id) async {
    await box.delete(id);
  }

  /// Update asset price
  Future<void> updateAssetPrice(String id, double newPrice) async {
    final asset = getAssetById(id);
    if (asset != null) {
      // Create updated copy and put back into box (more reliable on web/IndexedDB)
      final updated = asset.copyWith(
        currentPrice: newPrice,
        updatedAt: DateTime.now(),
        priceUpdatedAt: DateTime.now(),
      );
      await box.put(id, updated);
    }
  }

  /// Get total portfolio value
  double getTotalValue() {
    return box.values.fold(0.0, (sum, asset) => sum + asset.currentValue);
  }

  /// Get total invested amount
  double getTotalInvested() {
    return box.values.fold(0.0, (sum, asset) => sum + asset.totalInvested);
  }

  /// Get asset allocation by type
  Map<AssetType, double> getAssetAllocation() {
    final allocation = <AssetType, double>{};
    final totalValue = getTotalValue();
    
    if (totalValue == 0) return allocation;

    for (final type in AssetType.values) {
      final typeValue = box.values
          .where((asset) => asset.type == type)
          .fold(0.0, (sum, asset) => sum + asset.currentValue);
      
      if (typeValue > 0) {
        allocation[type] = (typeValue / totalValue) * 100;
      }
    }

    return allocation;
  }

  /// Get top gainers
  List<Asset> getTopGainers({int limit = 5}) {
    final assets = box.values.toList();
    assets.sort((a, b) => b.gainLossPercentage.compareTo(a.gainLossPercentage));
    return assets.where((a) => a.gainLossPercentage > 0).take(limit).toList();
  }

  /// Get top losers
  List<Asset> getTopLosers({int limit = 5}) {
    final assets = box.values.toList();
    assets.sort((a, b) => a.gainLossPercentage.compareTo(b.gainLossPercentage));
    return assets.where((a) => a.gainLossPercentage < 0).take(limit).toList();
  }

  /// Get unique platforms
  List<String> getUniquePlatforms() {
    return box.values
        .map((asset) => asset.platform)
        .where((platform) => platform != null && platform.isNotEmpty)
        .cast<String>()
        .toSet()
        .toList();
  }

  /// Export all assets to JSON
  List<Map<String, dynamic>> exportToJson() {
    return box.values.map((asset) => asset.toJson()).toList();
  }

  /// Import assets from JSON
  Future<void> importFromJson(List<Map<String, dynamic>> jsonList) async {
    for (final json in jsonList) {
      final asset = Asset.fromJson(json);
      await addAsset(asset);
    }
  }

  /// Get base currency from settings
  String getBaseCurrency() {
    return _settingsBox().get(AppConstants.keyBaseCurrency, defaultValue: 'INR') as String;
  }

  /// Save base currency to settings
  Future<void> setBaseCurrency(String currency) async {
    await _settingsBox().put(AppConstants.keyBaseCurrency, currency);
  }

  /// Clear all assets
  Future<void> clearAll() async {
    await box.clear();
  }
}
