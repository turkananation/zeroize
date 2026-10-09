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
  //
  // Counters are kept per container type so that a failing
  // [debugAssertNoLeaks] can say *which* container leaked instead of only how
  // many. The aggregate is the sum; see [liveSecretCount].
  static int _liveSecretBytes = 0;
  static int _liveSecretBuffers = 0;
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

  /// Number of currently live tracked secret containers.
  ///
  /// **This counts [SecretBytes] *and* [SecretBuffer].** Before 0.2.0 it
  /// counted only [SecretBytes], so a code path that allocated and dropped a
  /// [SecretBuffer] without disposing it reported `0` and passed
  /// [debugAssertNoLeaks]. The name is unchanged; the scope widened. Use
  /// [liveSecretBytesCount] or [liveSecretBufferCount] to separate them.
  ///
  /// Always `0` in release/AOT builds — tracking is a debug-only feature.
  static int get liveSecretCount => _liveSecretBytes + _liveSecretBuffers;

  /// Number of currently live [SecretBytes] instances.
  ///
  /// Always `0` in release/AOT builds.
  static int get liveSecretBytesCount => _liveSecretBytes;

  /// Number of currently live [SecretBuffer] instances.
  ///
  /// A [SecretBuffer] stops being counted once it is either [SecretBuffer.seal]ed
  /// or [SecretBuffer.dispose]d — both wipe the backing allocation, and this
  /// counter tracks *live secret material*, not live objects.
  ///
  /// Always `0` in release/AOT builds.
  static int get liveSecretBufferCount => _liveSecretBuffers;

  /// Total tracked secret containers allocated since this isolate started:
  /// [SecretBytes] plus [SecretBuffer].
  ///
  /// Always `0` in release/AOT builds.
  static int get totalAllocated => _totalAllocated;

  /// Asserts that all tracked secret containers have been disposed or sealed.
  ///
  /// Call in `tearDown()` of security-sensitive tests to detect leaks.
  /// No-op in release/AOT builds.
  ///
  /// ```dart
  /// tearDown(() => ZeroizeConfig.debugAssertNoLeaks());
  /// ```
  static void debugAssertNoLeaks() {
    assert(
      _liveSecretBytes == 0 && _liveSecretBuffers == 0,
      'ZeroizeConfig: ${_describeLeaks()}',
    );
  }

  /// Builds the assertion message, naming each container type that leaked.
  static String _describeLeaks() {
    if (_liveSecretBytes == 0 && _liveSecretBuffers == 0) return 'no leaks.';
    final parts = <String>[
      if (_liveSecretBytes > 0) '$_liveSecretBytes SecretBytes',
      if (_liveSecretBuffers > 0) '$_liveSecretBuffers SecretBuffer(s)',
    ];
    return '${parts.join(' and ')} were not disposed.';
  }

  // ─── Internal hooks ───────────────────────────────────────────────────────
  //
  // The un-suffixed hooks are [SecretBytes]'s and predate 0.2.0. They are kept
  // under their original names so the 0.1.0 -> 0.2.0 change is purely additive;
  // the buffer hooks are new and therefore explicit.

  /// Called by [SecretBytes] constructors. @nodoc
  static void trackAllocate() {
    assert(() {
      _liveSecretBytes++;
      _totalAllocated++;
      return true;
    }());
  }

  /// Called by [SecretBytes.dispose]. @nodoc
  static void trackDispose() {
    assert(() {
      _liveSecretBytes--;
      return true;
    }());
  }

  /// Called by the [SecretBuffer] constructor. @nodoc
  static void trackAllocateBuffer() {
    assert(() {
      _liveSecretBuffers++;
      _totalAllocated++;
      return true;
    }());
  }

  /// Called by [SecretBuffer.seal] and [SecretBuffer.dispose]. @nodoc
  static void trackDisposeBuffer() {
    assert(() {
      _liveSecretBuffers--;
      return true;
    }());
  }
}
