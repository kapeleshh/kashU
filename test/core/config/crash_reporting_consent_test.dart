import 'package:flutter_test/flutter_test.dart';
import 'package:kashu/core/config/crash_reporting_consent.dart';

void main() {
  group('crashReportingConsentGiven', () {
    test('explicit true grants consent', () {
      expect(crashReportingConsentGiven(true), isTrue);
    });

    test('explicit false denies consent', () {
      expect(crashReportingConsentGiven(false), isFalse);
    });

    test('missing value (null) denies consent — opt-in default', () {
      expect(crashReportingConsentGiven(null), isFalse);
    });

    test('corrupted non-bool values deny consent', () {
      expect(crashReportingConsentGiven('true'), isFalse);
      expect(crashReportingConsentGiven(1), isFalse);
      expect(crashReportingConsentGiven(<String, dynamic>{}), isFalse);
    });
  });
}
