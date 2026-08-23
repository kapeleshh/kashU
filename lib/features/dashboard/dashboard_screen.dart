import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_decorations.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/portfolio_summary_card.dart';
import '../../shared/widgets/asset_allocation_chart.dart';
import '../../shared/widgets/top_performers_list.dart';
import '../../shared/widgets/coin_mascot.dart';
import '../../shared/providers/portfolio_provider.dart';
import '../../services/widget_update_service.dart';
import '../assets/assets_screen.dart';
import '../assets/add_asset_screen.dart';
import '../transactions/transactions_screen.dart';
import '../settings/settings_screen.dart';

// Helper to refresh all prices and update the portfolio
Future<void> _doRefreshPrices(WidgetRef ref, BuildContext context) async {
  ref.read(isRefreshingPricesProvider.notifier).state = true;
  try {
    final service = ref.read(priceUpdateServiceProvider);
    final result = await service.refreshAllPrices();
    ref.read(lastRefreshResultProvider.notifier).state = result;

    // Persist the refresh timestamp so isPriceStaleProvider works after restart
    await Hive.box(AppConstants.settingsBox).put(
      'lastPriceRefreshAt',
      result.completedAt.toIso8601String(),
    );

    // Refresh portfolio data
    ref.invalidate(allAssetsProvider);
    ref.invalidate(portfolioSummaryProvider);

    // Update home screen widget with latest portfolio figures, and record a
    // daily price snapshot (drives today's-change + the detail sparkline).
    // Both use the summary's base-currency total; both are best-effort, but
    // a widget failure must never suppress the snapshot (on platforms
    // without the widget plugin it throws before the snapshot would run).
    try {
      final summary = await ref.read(portfolioSummaryProvider.future);
      try {
        await WidgetUpdateService.updatePortfolioWidget(
          totalValue: summary.totalValue,
          totalGainLoss: summary.totalGainLoss,
          gainLossPct: summary.totalGainLossPercentage,
          baseCurrency: ref.read(baseCurrencyProvider),
        );
      } catch (_) {
        // Widget update is best-effort.
      }

      final assets = ref.read(allAssetsProvider);
      if (assets.isNotEmpty) {
        await ref.read(priceHistoryServiceProvider).recordDailySnapshot(
              total: summary.totalValue,
              assetValues: {for (final a in assets) a.id: a.currentValue},
            );
      }
    } catch (_) {
      // Widget update + history are best-effort; never crash the refresh flow
    }

    // On success the status pill below the header is the only feedback;
    // a snack bar is shown only when some assets failed to refresh.
    if (context.mounted && result.hasErrors) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.summary),
          backgroundColor: AppColors.error,
          action: SnackBarAction(
            label: 'Details',
            textColor: Colors.white,
            onPressed: () => _showErrorDetails(context, result.errors),
          ),
        ),
      );
    }
  } finally {
    ref.read(isRefreshingPricesProvider.notifier).state = false;
  }
}

String _formatTime(DateTime dt) {
  final now = DateTime.now();
  final diff = now.difference(dt);
  if (diff.inSeconds < 60) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
}

({String text, String emoji}) _greeting() {
  final h = DateTime.now().hour;
  if (h < 12) return (text: 'Good morning', emoji: '☀️');
  if (h < 17) return (text: 'Good afternoon', emoji: '🌤️');
  return (text: 'Good evening', emoji: '🌙');
}

void _showErrorDetails(BuildContext context, List<String> errors) {
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Price Update Errors'),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: errors
              .map((e) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text('• $e', style: const TextStyle(fontSize: 13)),
                  ))
              .toList(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  int _currentIndex = 0;

  static const _settingsTabIndex = 3;

  final List<Widget> _screens = const [
    _DashboardContent(),
    AssetsScreen(),
    TransactionsScreen(),
    SettingsScreen(),
  ];

  void _switchToTab(int index) => setState(() => _currentIndex = index);

  Future<void> _openAddAsset() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AddAssetScreen()),
    );
    ref.invalidate(allAssetsProvider);
    ref.invalidate(portfolioSummaryProvider);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: _screens),
      // The dashboard owns the global "add" FAB; other tabs keep their own.
      floatingActionButton:
          _currentIndex == 0 ? _SoftFab(onTap: _openAddAsset) : null,
      bottomNavigationBar: _SoftBottomNav(
        currentIndex: _currentIndex,
        onTap: (i) => setState(() => _currentIndex = i),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Dashboard content
// ─────────────────────────────────────────────────────────────────────────────

class _DashboardContent extends ConsumerWidget {
  const _DashboardContent();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final portfolioAsync = ref.watch(portfolioSummaryProvider);
    final isRefreshing = ref.watch(isRefreshingPricesProvider);
    final lastResult = ref.watch(lastRefreshResultProvider);
    final isPriceStale = ref.watch(isPriceStaleProvider);
    final isBackupOverdue = ref.watch(isBackupOverdueProvider);
    final baseCurrency = ref.watch(baseCurrencyProvider);
    final greeting = _greeting();

    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: () => _doRefreshPrices(ref, context),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 130),
          children: [
            // Header
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${greeting.text} ${greeting.emoji}',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ),
                _RefreshButton(
                  isRefreshing: isRefreshing,
                  onTap: () => _doRefreshPrices(ref, context),
                ),
                const SizedBox(width: 10),
                const CoinMascot(),
              ],
            ),

            // Last refresh result, or a stale-price hint if we've never shown one.
            if (lastResult != null) ...[
              const SizedBox(height: 10),
              _StatusPill(
                icon: lastResult.hasErrors
                    ? Icons.warning_amber_rounded
                    : Icons.check_circle_rounded,
                color: lastResult.hasErrors
                    ? AppColors.error
                    : AppColors.gainOn(context),
                text: lastResult.summary,
                trailing: _formatTime(lastResult.completedAt),
                onTap: lastResult.hasErrors
                    ? () => _showErrorDetails(context, lastResult.errors)
                    : null,
              ),
            ] else if (isPriceStale) ...[
              const SizedBox(height: 10),
              _StatusPill(
                icon: Icons.schedule_rounded,
                color: AppColors.warning,
                text: 'Prices may be out of date — pull to refresh',
              ),
            ],

            // Backup nudge — the data only exists on this device.
            if (isBackupOverdue) ...[
              const SizedBox(height: 10),
              const _BackupNudgePill(),
            ],

            const SizedBox(height: 16),

            // Hero
            portfolioAsync.when(
              data: (summary) => PortfolioSummaryCard(
                  summary: summary, baseCurrency: baseCurrency),
              loading: () => const PortfolioSummaryCard.loading(),
              error: (e, _) => PortfolioSummaryCard.error(e.toString()),
            ),

            const SizedBox(height: 18),

            // Your mix
            portfolioAsync.when(
              data: (summary) => AssetAllocationChart(
                allocation: summary.assetAllocation,
                totalValue: summary.totalValue,
                assetCount: summary.totalAssets,
              ),
              loading: () => const AssetAllocationChart.loading(),
              error: (e, _) => const SizedBox.shrink(),
            ),

            const SizedBox(height: 20),

            // Best performers (all-time gainers)
            _SectionTitle('Best performers'),
            const SizedBox(height: 11),
            portfolioAsync.when(
              data: (summary) => summary.topGainers.isEmpty
                  ? const SizedBox.shrink()
                  : TopPerformersList(
                      assets: summary.topGainers, isGainers: true),
              loading: () => const TopPerformersList.loading(),
              error: (e, _) => const SizedBox.shrink(),
            ),

            // Underperformers (all-time losers) — only when there are any
            portfolioAsync.maybeWhen(
              data: (summary) => summary.topLosers.isEmpty
                  ? const SizedBox.shrink()
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 20),
                        _SectionTitle('Underperformers'),
                        const SizedBox(height: 11),
                        TopPerformersList(
                            assets: summary.topLosers, isGainers: false),
                      ],
                    ),
              orElse: () => const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 2),
      child: Text(text, style: Theme.of(context).textTheme.titleLarge),
    );
  }
}

class _RefreshButton extends StatelessWidget {
  final bool isRefreshing;
  final VoidCallback onTap;
  const _RefreshButton({required this.isRefreshing, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.avatar),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: isRefreshing ? null : onTap,
        child: SizedBox(
          width: 40,
          height: 40,
          child: isRefreshing
              ? const Padding(
                  padding: EdgeInsets.all(11),
                  child: CircularProgressIndicator(
                      strokeWidth: 2.2, color: AppColors.primary),
                )
              : Icon(Icons.refresh_rounded,
                  size: 20, color: AppColors.textSecondaryOn(context)),
        ),
      ),
    );
  }
}

/// Dismissible nudge shown when the portfolio hasn't been backed up for a
/// while (or ever). Tapping it switches to the Settings tab (where export
/// lives); dismissing snoozes it for [backupNudgePeriod].
class _BackupNudgePill extends ConsumerWidget {
  const _BackupNudgePill();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final color = AppColors.warning;
    return GestureDetector(
      onTap: () => context
          .findAncestorStateOfType<_DashboardScreenState>()
          ?._switchToTab(_DashboardScreenState._settingsTabIndex),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(AppRadii.small),
        ),
        child: Row(
          children: [
            Icon(Icons.backup_outlined, size: 14, color: color),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Your data lives only on this device — back it up',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.body(
                    size: 12, weight: FontWeight.w600, color: color),
              ),
            ),
            IconButton(
              icon: Icon(Icons.close_rounded, size: 16, color: color),
              padding: EdgeInsets.zero,
              constraints:
                  const BoxConstraints(minWidth: 32, minHeight: 32),
              tooltip: 'Dismiss for 30 days',
              onPressed: () async {
                await Hive.box(AppConstants.settingsBox).put(
                  AppConstants.keyBackupNudgeDismissedAt,
                  DateTime.now().toIso8601String(),
                );
                ref.invalidate(isBackupOverdueProvider);
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// A soft status pill (last-refresh summary, or a stale-price hint).
class _StatusPill extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;
  final String? trailing;
  final VoidCallback? onTap;

  const _StatusPill({
    required this.icon,
    required this.color,
    required this.text,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(AppRadii.small),
        ),
        child: Row(
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    AppTheme.body(size: 12, weight: FontWeight.w600, color: color),
              ),
            ),
            if (trailing != null)
              Text(
                trailing!,
                style: AppTheme.body(
                  size: 11,
                  color: AppColors.textTertiaryOn(context),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Floating bottom navigation + FAB
// ─────────────────────────────────────────────────────────────────────────────

class _SoftBottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const _SoftBottomNav({required this.currentIndex, required this.onTap});

  static const _items = [
    (icon: Icons.home_rounded, label: 'Home'),
    (icon: Icons.account_balance_wallet_rounded, label: 'Assets'),
    (icon: Icons.swap_horiz_rounded, label: 'Activity'),
    (icon: Icons.settings_rounded, label: 'Settings'),
  ];

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Container(
          height: 58,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(AppRadii.nav),
            boxShadow: AppShadows.soft(opacity: 0.30, y: 12, blur: 26),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              for (var i = 0; i < _items.length; i++) _navItem(context, i),
            ],
          ),
        ),
      ),
    );
  }

  Widget _navItem(BuildContext context, int i) {
    final item = _items[i];
    final selected = i == currentIndex;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onTap(i),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        padding:
            EdgeInsets.symmetric(horizontal: selected ? 13 : 10, vertical: 8),
        decoration: BoxDecoration(
          gradient: selected ? AppColors.primaryGradient : null,
          borderRadius: BorderRadius.circular(AppRadii.small),
          boxShadow:
              selected ? AppShadows.glow(AppColors.primary, opacity: 0.45) : null,
        ),
        child: Row(
          children: [
            Icon(
              item.icon,
              size: selected ? 20 : 22,
              color: selected ? Colors.white : AppColors.textTertiaryOn(context),
            ),
            if (selected) ...[
              const SizedBox(width: 6),
              Text(
                item.label,
                style: AppTheme.body(
                    size: 12, weight: FontWeight.w800, color: Colors.white),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SoftFab extends StatelessWidget {
  final VoidCallback onTap;
  const _SoftFab({required this.onTap});

  @override
  Widget build(BuildContext context) {
    // endFloat already clears the bottom nav; no extra lift needed.
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        gradient: AppColors.mintGradient,
        borderRadius: BorderRadius.circular(18),
        boxShadow: AppShadows.glow(const Color(0xFF10B981), opacity: 0.6),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: const Icon(Icons.add_rounded, color: Colors.white, size: 28),
        ),
      ),
    );
  }
}
