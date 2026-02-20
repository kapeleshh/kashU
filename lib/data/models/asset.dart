import 'package:hive/hive.dart';
import 'asset_type.dart';

part 'asset.g.dart';

/// Model representing an investment asset in the portfolio
@HiveType(typeId: 2)
class Asset extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  String name;

  @HiveField(2)
  String? symbol;

  @HiveField(3)
  AssetType type;

  @HiveField(4)
  double quantity;

  @HiveField(5)
  double purchasePrice;

  @HiveField(6)
  double currentPrice;

  @HiveField(7)
  String currency;

  @HiveField(8)
  DateTime purchaseDate;

  @HiveField(9)
  String? platform;

  @HiveField(10)
  String? notes;

  @HiveField(11)
  DateTime createdAt;

  @HiveField(12)
  DateTime updatedAt;

  @HiveField(13)
  DateTime? priceUpdatedAt;

  Asset({
    required this.id,
    required this.name,
    this.symbol,
    required this.type,
    required this.quantity,
    required this.purchasePrice,
    required this.currentPrice,
    required this.currency,
    required this.purchaseDate,
    this.platform,
    this.notes,
    required this.createdAt,
    required this.updatedAt,
    this.priceUpdatedAt,
  });

  /// Calculate total invested amount
  double get totalInvested => quantity * purchasePrice;

  /// Calculate current value
  double get currentValue => quantity * currentPrice;

  /// Calculate absolute gain/loss
  double get gainLoss => currentValue - totalInvested;

  /// Calculate percentage gain/loss
  double get gainLossPercentage {
    if (totalInvested == 0) return 0;
    return ((currentValue - totalInvested) / totalInvested) * 100;
  }

  /// Check if asset is in profit
  bool get isProfit => gainLoss >= 0;

  /// Create a copy with updated fields
  Asset copyWith({
    String? id,
    String? name,
    String? symbol,
    AssetType? type,
    double? quantity,
    double? purchasePrice,
    double? currentPrice,
    String? currency,
    DateTime? purchaseDate,
    String? platform,
    String? notes,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? priceUpdatedAt,
  }) {
    return Asset(
      id: id ?? this.id,
      name: name ?? this.name,
      symbol: symbol ?? this.symbol,
      type: type ?? this.type,
      quantity: quantity ?? this.quantity,
      purchasePrice: purchasePrice ?? this.purchasePrice,
      currentPrice: currentPrice ?? this.currentPrice,
      currency: currency ?? this.currency,
      purchaseDate: purchaseDate ?? this.purchaseDate,
      platform: platform ?? this.platform,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      priceUpdatedAt: priceUpdatedAt ?? this.priceUpdatedAt,
    );
  }

  /// Convert to JSON for export
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'symbol': symbol,
      'type': type.index,
      'quantity': quantity,
      'purchasePrice': purchasePrice,
      'currentPrice': currentPrice,
      'currency': currency,
      'purchaseDate': purchaseDate.toIso8601String(),
      'platform': platform,
      'notes': notes,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'priceUpdatedAt': priceUpdatedAt?.toIso8601String(),
    };
  }

  /// Create from JSON for import
  factory Asset.fromJson(Map<String, dynamic> json) {
    return Asset(
      id: json['id'] as String,
      name: json['name'] as String,
      symbol: json['symbol'] as String?,
      type: AssetType.values[json['type'] as int],
      quantity: (json['quantity'] as num).toDouble(),
      purchasePrice: (json['purchasePrice'] as num).toDouble(),
      currentPrice: (json['currentPrice'] as num).toDouble(),
      currency: json['currency'] as String,
      purchaseDate: DateTime.parse(json['purchaseDate'] as String),
      platform: json['platform'] as String?,
      notes: json['notes'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      priceUpdatedAt: json['priceUpdatedAt'] != null 
          ? DateTime.parse(json['priceUpdatedAt'] as String)
          : null,
    );
  }

  @override
  String toString() {
    return 'Asset(id: $id, name: $name, type: ${type.displayName}, quantity: $quantity, currentValue: $currentValue)';
  }
}
