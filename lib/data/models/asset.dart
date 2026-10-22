import 'package:hive/hive.dart';
import '../../services/fd_bond_calculator.dart';
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

  // ── Deposit terms (schema v2) ─────────────────────────────────────────
  // Set only on a fixed/recurring deposit entered through the deposit
  // calculator, so its value can grow every day without a price refresh.
  // The start date is [purchaseDate] and an FD's principal is
  // [purchasePrice]. Older deposits have none of these and stay manually
  // valued through [currentPrice].

  /// Annual interest rate, e.g. 7.5 for 7.5% p.a.
  @HiveField(14)
  double? depositRatePercent;

  @HiveField(15)
  DateTime? depositMaturityDate;

  /// A fixed deposit's [CompoundingFrequency], by name. Null for an RD,
  /// which compounds monthly.
  @HiveField(16)
  String? depositCompounding;

  /// A recurring deposit's monthly instalment. Its presence is what makes
  /// the deposit an RD rather than an FD.
  @HiveField(17)
  double? rdMonthlyInstalment;

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
    this.depositRatePercent,
    this.depositMaturityDate,
    this.depositCompounding,
    this.rdMonthlyInstalment,
  });

  /// The deposit's terms when it has a complete set, else null — a
  /// manually valued holding (every non-deposit, and deposits saved before
  /// the terms were kept).
  DepositSchedule? get depositSchedule {
    if (type != AssetType.fixedDeposit && type != AssetType.bond) return null;
    final rate = depositRatePercent;
    final maturity = depositMaturityDate;
    if (rate == null || maturity == null || !maturity.isAfter(purchaseDate)) {
      return null;
    }
    final instalment = rdMonthlyInstalment;
    final compounding = instalment != null
        ? CompoundingFrequency.monthly
        : CompoundingFrequency.fromName(depositCompounding);
    if (compounding == null) return null;
    return DepositSchedule(
      startDate: purchaseDate,
      maturityDate: maturity,
      annualRatePercent: rate,
      principal: purchasePrice,
      compounding: compounding,
      monthlyInstalment: instalment,
    );
  }

  /// Whether this holding is valued from its deposit terms.
  bool get hasDepositSchedule => depositSchedule != null;

  /// Price per unit on [day]: a scheduled deposit's value then (capped at
  /// maturity), otherwise the stored [currentPrice].
  double currentPriceOn(DateTime day) =>
      depositSchedule?.valueAsOf(day) ?? currentPrice;

  /// Cost per unit on [day]: an RD's instalments paid by then, otherwise
  /// [purchasePrice].
  double investedPriceOn(DateTime day) =>
      depositSchedule?.investedAsOf(day) ?? purchasePrice;

  /// Price per unit today — what a screen should show wherever it would
  /// show [currentPrice]. Equal to it for anything without deposit terms.
  double get effectiveCurrentPrice => currentPriceOn(DateTime.now());

  /// Calculate total invested amount (an RD's grows with each instalment)
  double get totalInvested => quantity * investedPriceOn(DateTime.now());

  /// Calculate current value (a scheduled deposit's grows daily)
  double get currentValue => quantity * effectiveCurrentPrice;

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
    double? depositRatePercent,
    DateTime? depositMaturityDate,
    String? depositCompounding,
    double? rdMonthlyInstalment,
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
      depositRatePercent: depositRatePercent ?? this.depositRatePercent,
      depositMaturityDate: depositMaturityDate ?? this.depositMaturityDate,
      depositCompounding: depositCompounding ?? this.depositCompounding,
      rdMonthlyInstalment: rdMonthlyInstalment ?? this.rdMonthlyInstalment,
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
      // Backup format v3. Null for anything without deposit terms.
      'depositRatePercent': depositRatePercent,
      'depositMaturityDate': depositMaturityDate?.toIso8601String(),
      'depositCompounding': depositCompounding,
      'rdMonthlyInstalment': rdMonthlyInstalment,
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
      // Absent from v1/v2 backups: those deposits stay manually valued.
      depositRatePercent: (json['depositRatePercent'] as num?)?.toDouble(),
      depositMaturityDate: json['depositMaturityDate'] != null
          ? DateTime.parse(json['depositMaturityDate'] as String)
          : null,
      depositCompounding: json['depositCompounding'] as String?,
      rdMonthlyInstalment: (json['rdMonthlyInstalment'] as num?)?.toDouble(),
    );
  }

  @override
  String toString() {
    return 'Asset(id: $id, name: $name, type: ${type.displayName}, quantity: $quantity, currentValue: $currentValue)';
  }
}
