import 'package:hive/hive.dart';
import 'transaction_type.dart';

part 'transaction.g.dart';

/// Model representing a transaction (buy, sell, dividend, interest)
@HiveType(typeId: 3)
class Transaction extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String assetId;

  @HiveField(2)
  TransactionType type;

  @HiveField(3)
  double quantity;

  @HiveField(4)
  double price;

  @HiveField(5)
  double amount;

  @HiveField(6)
  String currency;

  @HiveField(7)
  DateTime date;

  @HiveField(8)
  String? notes;

  @HiveField(9)
  DateTime createdAt;

  Transaction({
    required this.id,
    required this.assetId,
    required this.type,
    required this.quantity,
    required this.price,
    required this.amount,
    required this.currency,
    required this.date,
    this.notes,
    required this.createdAt,
  });

  /// Create a copy with updated fields
  Transaction copyWith({
    String? id,
    String? assetId,
    TransactionType? type,
    double? quantity,
    double? price,
    double? amount,
    String? currency,
    DateTime? date,
    String? notes,
    DateTime? createdAt,
  }) {
    return Transaction(
      id: id ?? this.id,
      assetId: assetId ?? this.assetId,
      type: type ?? this.type,
      quantity: quantity ?? this.quantity,
      price: price ?? this.price,
      amount: amount ?? this.amount,
      currency: currency ?? this.currency,
      date: date ?? this.date,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  /// Convert to JSON for export
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'assetId': assetId,
      'type': type.index,
      'quantity': quantity,
      'price': price,
      'amount': amount,
      'currency': currency,
      'date': date.toIso8601String(),
      'notes': notes,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  /// Create from JSON for import
  factory Transaction.fromJson(Map<String, dynamic> json) {
    return Transaction(
      id: json['id'] as String,
      assetId: json['assetId'] as String,
      type: TransactionType.values[json['type'] as int],
      quantity: (json['quantity'] as num).toDouble(),
      price: (json['price'] as num).toDouble(),
      amount: (json['amount'] as num).toDouble(),
      currency: json['currency'] as String,
      date: DateTime.parse(json['date'] as String),
      notes: json['notes'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }

  @override
  String toString() {
    return 'Transaction(id: $id, assetId: $assetId, type: ${type.displayName}, amount: $amount)';
  }
}
