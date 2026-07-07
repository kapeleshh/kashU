import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';
import '../models/transaction.dart';
import '../models/transaction_type.dart';
import '../models/asset.dart';
import '../../core/constants/app_constants.dart';

/// Repository for managing Transaction data in Hive
class TransactionRepository {
  Box<Transaction>? _box;

  Box<Transaction> get box {
    _box ??= Hive.box<Transaction>(AppConstants.transactionsBox);
    return _box!;
  }

  /// Get all transactions sorted by date (newest first)
  List<Transaction> getAllTransactions() {
    final transactions = box.values.toList();
    transactions.sort((a, b) => b.date.compareTo(a.date));
    return transactions;
  }

  /// Get transactions for a specific asset
  List<Transaction> getTransactionsForAsset(String assetId) {
    return box.values
        .where((t) => t.assetId == assetId)
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));
  }

  /// Get transactions by type
  List<Transaction> getTransactionsByType(TransactionType type) {
    return box.values.where((t) => t.type == type).toList();
  }

  /// Add a new transaction
  Future<void> addTransaction(Transaction transaction) async {
    await box.put(transaction.id, transaction);
  }

  /// Log a BUY transaction when an asset is added
  Future<void> logBuyTransaction(Asset asset) async {
    final transaction = Transaction(
      id: const Uuid().v4(),
      assetId: asset.id,
      type: TransactionType.buy,
      quantity: asset.quantity,
      price: asset.purchasePrice,
      amount: asset.totalInvested,
      currency: asset.currency,
      date: asset.purchaseDate,
      notes: 'Initial purchase',
      createdAt: DateTime.now(),
    );
    await addTransaction(transaction);
  }

  /// Delete a transaction
  Future<void> deleteTransaction(String id) async {
    await box.delete(id);
  }

  /// Delete all transactions for a specific asset
  Future<void> deleteTransactionsForAsset(String assetId) async {
    final keys = box.values
        .where((t) => t.assetId == assetId)
        .map((t) => t.id)
        .toList();
    await box.deleteAll(keys);
  }

  /// Get total transaction count
  int get totalTransactions => box.length;

  /// Export all transactions to JSON
  List<Map<String, dynamic>> exportToJson() {
    return box.values.map((t) => t.toJson()).toList();
  }

  /// Import transactions from JSON
  Future<void> importFromJson(List<Map<String, dynamic>> jsonList) async {
    for (final json in jsonList) {
      final transaction = Transaction.fromJson(json);
      await addTransaction(transaction);
    }
  }

  /// Clear all transactions
  Future<void> clearAll() async {
    await box.clear();
  }
}
