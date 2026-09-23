import '../core/overwrite_patterns.dart';

/// Global configuration for the zeroize package.
///
/// Configure before performing any zeroize operations — typically in `main()`
/// or during library initialisation.  Not thread-safe across isolates; each
/// isolate maintains its own copy of the static state.
///
/// ```dart
/// void main() {
///   ZeroizeConfig.setDefaultPattern(ZeroizePattern.dod);
///   runApp();
/// }
/// ```
abstract final class ZeroizeConfig {
  static ZeroizePattern _defaultPattern = ZeroizePattern.twoPass;

  // Debug allocation counters — zero-cost in release/AOT builds because
  // they are only updated inside `assert()` closures.
  static int _liveCount = 0;
  static int _totalAllocated = 0;

  // ─── Public API ───────────────────────────────────────────────────────────

  /// The default [ZeroizePattern] applied when no explicit pattern is passed
  /// to [secureZero] or any container constructor.
  ///
  /// Defaults to [ZeroizePattern.twoPass].
  static ZeroizePattern get defaultPattern => _defaultPattern;

  /// Replaces the default [ZeroizePattern] for all subsequent operations
  /// that do not specify one explicitly.
  static void setDefaultPattern(ZeroizePattern pattern) {
    _defaultPattern = pattern;
  }

  // ─── Debug tracking (debug/test builds only) ──────────────────────────────

  /// Number of currently live [SecretBytes] instances.
  ///
  /// Always `0` in release/AOT builds — tracking is a debug-only feature.
  static int get liveSecretCount => _liveCount;

  /// Total [SecretBytes] instances allocated since this isolate started.
  ///
  /// Always `0` in release/AOT builds.
  static int get totalAllocated => _totalAllocated;

  /// Asserts that all tracked [SecretBytes] instances have been disposed.
  ///
  /// Call in `tearDown()` of security-sensitive tests to detect leaks.
  /// No-op in release/AOT builds.
  ///
  /// ```dart
  /// tearDown(() => ZeroizeConfig.debugAssertNoLeaks());
  /// ```
  static void debugAssertNoLeaks() {
    assert(
      _liveCount == 0,
      'ZeroizeConfig: $_liveCount SecretBytes instance(s) were not disposed.',
    );
  }

  // ─── Internal hooks ───────────────────────────────────────────────────────

  /// Called by [SecretBytes] constructors. @nodoc
  static void trackAllocate() {
    assert(() {
      _liveCount++;
      _totalAllocated++;
      return true;
    }());
  }

  /// Called by [SecretBytes.dispose]. @nodoc
  static void trackDispose() {
    assert(() {
      _liveCount--;
      return true;
    }());
  }
}
