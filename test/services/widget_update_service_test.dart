import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kashu/services/widget_update_service.dart';

const _channel = MethodChannel('home_widget');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<MethodCall> calls;

  setUp(() {
    calls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
      calls.add(call);
      return true;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });

  test('clearing the widget removes every figure, then redraws it', () async {
    await WidgetUpdateService.clearPortfolioWidget();

    final saves = calls.where((c) => c.method == 'saveWidgetData').toList();
    expect(
      {
        for (final c in saves)
          (c.arguments as Map)['id']: (c.arguments as Map)['data']
      },
      {
        'portfolio_value': null,
        'gain_loss': null,
        'gain_loss_pct': null,
        'is_positive': null,
      },
    );
    expect(calls.last.method, 'updateWidget');
  });

  test('the cleared keys are exactly the ones an update writes', () async {
    await WidgetUpdateService.updatePortfolioWidget(
      totalValue: 1000,
      totalGainLoss: 100,
      gainLossPct: 10,
      baseCurrency: 'INR',
    );

    final written = calls
        .where((c) => c.method == 'saveWidgetData')
        .map((c) => (c.arguments as Map)['id'])
        .toSet();
    expect(written, WidgetUpdateService.widgetDataKeys.toSet());
  });
}
