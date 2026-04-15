/// Retry with exponential backoff for network operations.
///
/// Usage:
/// ```dart
/// final result = await RetryHelper.withRetry(
///   action: () => myService.fetchPrice('AAPL'),
///   isFailure: (r) => !r.success,
/// );
/// ```
abstract final class RetryHelper {
  /// Executes [action] up to [maxAttempts] times, retrying when [isFailure]
  /// returns true for the result.
  ///
  /// Delays between attempts follow exponential backoff:
  ///   delay_n = initialDelay * backoffFactor^(n-1)
  ///
  /// e.g. with defaults: 1 s → 2 s → (3rd attempt is last, no extra wait)
  ///
  /// If [shouldRetry] is null, the action is retried on any non-success as
  /// determined by [isFailure].
  ///
  /// On all retries exhausted, the last result is returned (never throws).
  static Future<T> withRetry<T>({
    required Future<T> Function() action,
    required bool Function(T) isFailure,
    int maxAttempts = 3,
    Duration initialDelay = const Duration(seconds: 1),
    double backoffFactor = 2.0,
    bool Function(T)? isRetriable,
  }) async {
    T? last;
    Duration delay = initialDelay;

    for (int attempt = 1; attempt <= maxAttempts; attempt++) {
      last = await action();

      // Return immediately on success
      if (!isFailure(last)) return last;

      // Check if this specific failure type is worth retrying
      if (isRetriable != null && !isRetriable(last)) return last;

      // No more retries after last attempt
      if (attempt == maxAttempts) break;

      await Future<void>.delayed(delay);
      delay = Duration(
        milliseconds: (delay.inMilliseconds * backoffFactor).round(),
      );
    }

    return last as T;
  }
}
