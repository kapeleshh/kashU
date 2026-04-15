/// Lightweight Result type for operations that can succeed or fail.
///
/// Usage:
/// ```dart
/// Result<MyData> fetchSomething() async {
///   try {
///     return Ok(await doWork());
///   } catch (e) {
///     return Err('Failed: $e');
///   }
/// }
///
/// final result = await fetchSomething();
/// switch (result) {
///   case Ok(:final value): print(value);
///   case Err(:final message): print(message);
/// }
/// ```
sealed class Result<T> {
  const Result();

  bool get isOk => this is Ok<T>;
  bool get isErr => this is Err<T>;

  /// Returns the value if Ok, or null if Err.
  T? get valueOrNull => switch (this) {
        Ok(:final value) => value,
        Err() => null,
      };

  /// Returns the error message if Err, or null if Ok.
  String? get errorOrNull => switch (this) {
        Err(:final message) => message,
        Ok() => null,
      };

  /// Maps the Ok value to a different type.
  Result<U> map<U>(U Function(T value) transform) => switch (this) {
        Ok(:final value) => Ok(transform(value)),
        Err(:final message) => Err(message),
      };
}

/// Represents a successful result containing a [value].
final class Ok<T> extends Result<T> {
  final T value;
  const Ok(this.value);

  @override
  String toString() => 'Ok($value)';
}

/// Represents a failed result containing an error [message].
final class Err<T> extends Result<T> {
  final String message;
  const Err(this.message);

  @override
  String toString() => 'Err($message)';
}
