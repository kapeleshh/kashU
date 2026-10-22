import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';

/// Whether this build can send crash reports at all, i.e. a Sentry DSN was
/// baked in with `--dart-define=SENTRY_DSN=…`. Without one, the Settings
/// opt-in switch would do nothing, so it is not shown.
///
/// [AppConfig] is compile-time constant; this provider is the seam widget
/// tests override to exercise both kinds of build.
final crashReportingAvailableProvider =
    Provider<bool>((ref) => AppConfig.isSentryEnabled);
