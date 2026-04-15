import 'package:home_widget/home_widget.dart';

import '../core/utils/currency_formatter.dart';

/// Identifier used in AndroidManifest.xml and AppWidgetProvider.
const String _kAndroidWidgetName =
    'com.kashu.app.widget.PortfolioWidgetProvider';

/// App group ID for iOS WidgetKit data sharing.
const String _kIosAppGroup = 'group.com.kashu.app.widget';

/// Updates the native home screen widget with current portfolio data.
///
/// On Android this triggers a broadcast to [_kAndroidWidgetName] which
/// re-reads the shared preferences written here and calls `RemoteViews.apply`.
///
/// On iOS the shared UserDefaults (via app group [_kIosAppGroup]) are written
/// here; the WidgetKit timeline provider reads them on the next refresh.
///
/// Call after every successful price refresh and after any transaction that
/// changes portfolio value.
class WidgetUpdateService {
  /// Write portfolio data to shared storage and notify the native widget.
  static Future<void> updatePortfolioWidget({
    required double totalValue,
    required double totalGainLoss,
    required double gainLossPct,
    required String baseCurrency,
  }) async {
    await HomeWidget.setAppGroupId(_kIosAppGroup);

    final valueStr = CurrencyFormatter.formatCurrency(totalValue, baseCurrency);
    final gainStr = CurrencyFormatter.formatCurrency(
        totalGainLoss.abs(), baseCurrency);
    final pctStr =
        '${totalGainLoss >= 0 ? '+' : '-'}${gainLossPct.abs().toStringAsFixed(2)}%';
    final isPositive = totalGainLoss >= 0;

    await Future.wait([
      HomeWidget.saveWidgetData<String>('portfolio_value', valueStr),
      HomeWidget.saveWidgetData<String>('gain_loss', gainStr),
      HomeWidget.saveWidgetData<String>('gain_loss_pct', pctStr),
      HomeWidget.saveWidgetData<bool>('is_positive', isPositive),
    ]);

    await HomeWidget.updateWidget(
      androidName: _kAndroidWidgetName,
      iOSName: 'PortfolioWidget',
    );
  }
}
