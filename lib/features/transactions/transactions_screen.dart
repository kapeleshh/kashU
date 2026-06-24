import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_strings.dart';
import '../../core/theme/app_decorations.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/currency_formatter.dart';
import '../../data/models/transaction.dart';
import '../../data/models/transaction_type.dart';
import '../../shared/providers/portfolio_provider.dart';

class TransactionsScreen extends ConsumerStatefulWidget {
  const TransactionsScreen({super.key});

  @override
  ConsumerState<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends ConsumerState<TransactionsScreen> {
  TransactionType? _activeFilter; // null = show all

  @override
  Widget build(BuildContext context) {
    final txRepo = ref.watch(transactionRepositoryProvider);
    final assetRepo = ref.watch(assetRepositoryProvider);

    // Build asset-name lookup map once per build
    final assetNames = {
      for (final a in assetRepo.getAllAssets()) a.id: a.name,
    };

    // Apply filter
    final allTransactions = txRepo.getAllTransactions();
    final transactions = _activeFilter == null
        ? allTransactions
        : allTransactions.where((t) => t.type == _activeFilter).toList();

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header — "Activity" + month · count
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: _Header(count: allTransactions.length),
            ),

            const SizedBox(height: 14),

            // Filter pills
            _FilterBar(
              activeFilter: _activeFilter,
              onFilterChanged: (f) => setState(() => _activeFilter = f),
            ),

            // Filtered-count hint
            if (allTransactions.isNotEmpty && _activeFilter != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 10, 18, 0),
                child: Text(
                  '${transactions.length} of ${allTransactions.length}',
                  style: AppTheme.body(
                    size: 12,
                    weight: FontWeight.w700,
                    color: AppColors.textTertiaryOn(context),
                  ),
                ),
              ),

            // List
            Expanded(
              child: transactions.isEmpty
                  ? _EmptyState(
                      noneAtAll: allTransactions.isEmpty,
                      filterName: _activeFilter?.displayName,
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 110),
                      itemCount: transactions.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 9),
                      itemBuilder: (context, index) {
                        final transaction = transactions[index];
                        return _TransactionCard(
                          transaction: transaction,
                          assetName: assetNames[transaction.assetId],
                          onDelete: () => _deleteTransaction(transaction),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteTransaction(Transaction transaction) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Transaction'),
        content: const Text('This will permanently remove this transaction.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(AppStrings.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              AppStrings.delete,
              style: TextStyle(color: AppColors.lossOn(context)),
            ),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      await ref
          .read(transactionRepositoryProvider)
          .deleteTransaction(transaction.id);
      setState(() {}); // rebuild to reflect deletion
    }
  }
}

// ─── Header ─────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  final int count;
  const _Header({required this.count});

  static const _months = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December'
  ];

  @override
  Widget build(BuildContext context) {
    final month = _months[DateTime.now().month - 1];
    final subtitle = count == 0
        ? month
        : '$month · $count transaction${count == 1 ? '' : 's'}';

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Activity',
                style: AppTheme.heading(
                  size: 22,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: AppTheme.body(
                  size: 12.5,
                  weight: FontWeight.w700,
                  color: AppColors.textSecondaryOn(context),
                ),
              ),
            ],
          ),
        ),
        Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(AppRadii.avatar),
            boxShadow: AppShadows.soft(opacity: 0.16, y: 8, blur: 18),
          ),
          child: Icon(
            Icons.swap_horiz_rounded,
            size: 20,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
      ],
    );
  }
}

// ─── Filter bar ───────────────────────────────────────────────────────────────

class _FilterBar extends StatelessWidget {
  final TransactionType? activeFilter;
  final ValueChanged<TransactionType?> onFilterChanged;

  const _FilterBar({
    required this.activeFilter,
    required this.onFilterChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          _FilterChip(
            label: 'All',
            isSelected: activeFilter == null,
            onTap: () => onFilterChanged(null),
          ),
          const SizedBox(width: 9),
          ...TransactionType.values.map(
            (type) => Padding(
              padding: const EdgeInsets.only(right: 9),
              child: _FilterChip(
                label: type.displayName,
                isSelected: activeFilter == type,
                onTap: () => onFilterChanged(
                  activeFilter == type ? null : type,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          gradient: isSelected ? AppColors.primaryGradient : null,
          color: isSelected ? null : Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(AppRadii.pill),
          boxShadow: isSelected
              ? AppShadows.glow(AppColors.primary, opacity: 0.40)
              : AppShadows.soft(opacity: 0.12, y: 6, blur: 14),
        ),
        child: Text(
          label,
          style: AppTheme.body(
            size: 11.5,
            weight: FontWeight.w800,
            color: isSelected
                ? Colors.white
                : AppColors.textSecondaryOn(context),
          ),
        ),
      ),
    );
  }
}

// ─── Transaction card ─────────────────────────────────────────────────────────

class _TransactionCard extends StatelessWidget {
  final Transaction transaction;
  final String? assetName;
  final VoidCallback onDelete;

  const _TransactionCard({
    required this.transaction,
    required this.assetName,
    required this.onDelete,
  });

  /// Pastel tone keyed to the transaction type (drives the square tag avatar).
  Color get _tagBase {
    switch (transaction.type) {
      case TransactionType.buy:
        return AppColors.cryptoColor; // pink
      case TransactionType.sell:
        return AppColors.stockColor; // mint
      case TransactionType.dividend:
        return AppColors.fdColor; // lavender
      case TransactionType.interest:
        return AppColors.bondColor; // cyan
    }
  }

  /// Short uppercase label shown inside the tag avatar.
  String get _tag {
    switch (transaction.type) {
      case TransactionType.buy:
        return 'BUY';
      case TransactionType.sell:
        return 'SELL';
      case TransactionType.dividend:
        return 'DIV';
      case TransactionType.interest:
        return 'INT';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isInflow = transaction.type.isInflow;
    // Money out (buy) reads as a loss tone; money in reads as a gain tone.
    final amountColor = transaction.type == TransactionType.buy
        ? AppColors.lossOn(context)
        : AppColors.gainOn(context);

    final title = assetName ?? transaction.type.displayName;

    return Dismissible(
      key: ValueKey(transaction.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 22),
        decoration: BoxDecoration(
          color: AppColors.lossOn(context).withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(AppRadii.tile),
        ),
        child: Icon(Icons.delete_outline_rounded,
            color: AppColors.lossOn(context)),
      ),
      confirmDismiss: (_) async {
        onDelete();
        return false; // deletion handled manually via dialog
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(AppRadii.tile),
          boxShadow: AppShadows.soft(opacity: 0.16, y: 10, blur: 24),
        ),
        child: Row(
          children: [
            // Square tag avatar
            Container(
              width: 42,
              height: 42,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: softAvatarGradient(_tagBase),
                borderRadius: BorderRadius.circular(AppRadii.avatar),
              ),
              child: Text(
                _tag,
                style: AppTheme.body(
                  size: 9.5,
                  weight: FontWeight.w800,
                  color: Colors.white,
                ).copyWith(letterSpacing: 0.5),
              ),
            ),
            const SizedBox(width: 12),

            // Asset name + subtitle
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.heading(
                      size: 14,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    _subtitle(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.body(
                      size: 11,
                      weight: FontWeight.w600,
                      color: AppColors.textSecondaryOn(context),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),

            // Amount + date
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${isInflow ? '+' : '-'}${CurrencyFormatter.formatINR(transaction.amount)}',
                  style: AppTheme.heading(size: 13.5, color: amountColor),
                ),
                const SizedBox(height: 2),
                Text(
                  _formatDate(transaction.date),
                  style: AppTheme.body(
                    size: 11,
                    weight: FontWeight.w700,
                    color: AppColors.textTertiaryOn(context),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Subtitle: prefer "qty @ price", else the type name; append notes if present.
  String _subtitle() {
    final parts = <String>[];
    if (transaction.quantity > 0) {
      parts.add(
        '${CurrencyFormatter.formatQuantity(transaction.quantity)} @ ${CurrencyFormatter.formatINR(transaction.price)}',
      );
    } else {
      parts.add(transaction.type.displayName);
    }
    if (transaction.notes != null && transaction.notes!.trim().isNotEmpty) {
      parts.add(transaction.notes!.trim());
    }
    return parts.join(' · ');
  }

  static String _formatDate(DateTime dt) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${dt.day} ${months[dt.month - 1]}';
  }
}

// ─── Empty state ──────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final bool noneAtAll;
  final String? filterName;

  const _EmptyState({required this.noneAtAll, required this.filterName});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 76,
              height: 76,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppRadii.card),
              ),
              child: Icon(
                Icons.swap_horiz_rounded,
                size: 38,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              noneAtAll
                  ? AppStrings.noTransactions
                  : 'No ${filterName ?? ''} transactions',
              textAlign: TextAlign.center,
              style: AppTheme.heading(
                size: 16,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              noneAtAll
                  ? 'Add an asset to see your activity here ✨'
                  : 'Try a different filter',
              textAlign: TextAlign.center,
              style: AppTheme.body(
                size: 13,
                weight: FontWeight.w600,
                color: AppColors.textSecondaryOn(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
