import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_constants.dart';
import '../../core/constants/app_strings.dart';
import '../../core/utils/currency_formatter.dart';
import '../../data/models/transaction.dart';
import '../../data/models/transaction_type.dart';

class TransactionsScreen extends ConsumerWidget {
  const TransactionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(AppStrings.transactions),
      ),
      body: ValueListenableBuilder(
        valueListenable: Hive.box<Transaction>(AppConstants.transactionsBox).listenable(),
        builder: (context, Box<Transaction> box, _) {
          final transactions = box.values.toList()
            ..sort((a, b) => b.date.compareTo(a.date));

          if (transactions.isEmpty) {
            return _buildEmptyState();
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: transactions.length,
            itemBuilder: (context, index) {
              final transaction = transactions[index];
              return _TransactionCard(transaction: transaction);
            },
          );
        },
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.swap_horiz,
            size: 80,
            color: AppColors.textTertiary,
          ),
          const SizedBox(height: 16),
          Text(
            AppStrings.noTransactions,
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Transactions will appear here when you add assets',
            style: TextStyle(
              color: AppColors.textTertiary,
              fontSize: 14,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _TransactionCard extends StatelessWidget {
  final Transaction transaction;

  const _TransactionCard({required this.transaction});

  @override
  Widget build(BuildContext context) {
    final isInflow = transaction.type.isInflow;
    final color = transaction.type.color;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: color.withOpacity(0.15),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            transaction.type.icon,
            color: color,
            size: 22,
          ),
        ),
        title: Text(
          transaction.type.displayName,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          '${transaction.date.day}/${transaction.date.month}/${transaction.date.year}',
          style: TextStyle(color: AppColors.textTertiary),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '${isInflow ? '+' : '-'}${CurrencyFormatter.formatINR(transaction.amount)}',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
            if (transaction.quantity > 0)
              Text(
                '${CurrencyFormatter.formatQuantity(transaction.quantity)} @ ${CurrencyFormatter.formatINR(transaction.price)}',
                style: TextStyle(
                  color: AppColors.textTertiary,
                  fontSize: 12,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
