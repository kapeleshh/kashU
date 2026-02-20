import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_strings.dart';
import '../../shared/widgets/portfolio_summary_card.dart';
import '../../shared/widgets/asset_allocation_chart.dart';
import '../../shared/widgets/top_performers_list.dart';
import '../../shared/providers/portfolio_provider.dart';
import '../assets/assets_screen.dart';
import '../transactions/transactions_screen.dart';
import '../settings/settings_screen.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  int _currentIndex = 0;

  final List<Widget> _screens = [
    const _DashboardContent(),
    const AssetsScreen(),
    const TransactionsScreen(),
    const SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border(
            top: BorderSide(
              color: AppColors.divider,
              width: 0.5,
            ),
          ),
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (index) => setState(() => _currentIndex = index),
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.dashboard_outlined),
              activeIcon: Icon(Icons.dashboard),
              label: AppStrings.dashboard,
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.account_balance_wallet_outlined),
              activeIcon: Icon(Icons.account_balance_wallet),
              label: AppStrings.assets,
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.swap_horiz_outlined),
              activeIcon: Icon(Icons.swap_horiz),
              label: AppStrings.transactions,
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.settings_outlined),
              activeIcon: Icon(Icons.settings),
              label: AppStrings.settings,
            ),
          ],
        ),
      ),
    );
  }
}

class _DashboardContent extends ConsumerWidget {
  const _DashboardContent();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final portfolioAsync = ref.watch(portfolioSummaryProvider);

    return SafeArea(
      child: CustomScrollView(
        slivers: [
          // App Bar
          SliverAppBar(
            floating: true,
            title: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    gradient: AppColors.primaryGradient,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Center(
                    child: Text(
                      'K',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                const Text(
                  AppStrings.appName,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: () {
                  ref.invalidate(portfolioSummaryProvider);
                },
              ),
            ],
          ),

          // Content
          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // Portfolio Summary Card
                portfolioAsync.when(
                  data: (summary) => PortfolioSummaryCard(summary: summary),
                  loading: () => const PortfolioSummaryCard.loading(),
                  error: (e, _) => PortfolioSummaryCard.error(e.toString()),
                ),

                const SizedBox(height: 24),

                // Asset Allocation Section
                Text(
                  AppStrings.assetAllocation,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                portfolioAsync.when(
                  data: (summary) => AssetAllocationChart(
                    allocation: summary.assetAllocation,
                  ),
                  loading: () => const AssetAllocationChart.loading(),
                  error: (e, _) => const SizedBox.shrink(),
                ),

                const SizedBox(height: 24),

                // Top Gainers
                Text(
                  AppStrings.topGainers,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                portfolioAsync.when(
                  data: (summary) => TopPerformersList(
                    assets: summary.topGainers,
                    isGainers: true,
                  ),
                  loading: () => const TopPerformersList.loading(),
                  error: (e, _) => const SizedBox.shrink(),
                ),

                const SizedBox(height: 24),

                // Top Losers
                Text(
                  AppStrings.topLosers,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                portfolioAsync.when(
                  data: (summary) => TopPerformersList(
                    assets: summary.topLosers,
                    isGainers: false,
                  ),
                  loading: () => const TopPerformersList.loading(),
                  error: (e, _) => const SizedBox.shrink(),
                ),

                const SizedBox(height: 100),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}
