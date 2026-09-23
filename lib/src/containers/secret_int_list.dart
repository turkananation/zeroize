import '../config/zeroize_config.dart';
import '../core/overwrite_patterns.dart';
import '../core/secure_zero.dart';
import '../errors.dart';
import '../lifecycle/zeroizable.dart';

// Finalizer token type for SecretIntList.
typedef _IntListToken = ({List<int> data, ZeroizePattern pattern});

final _intListFinalizer = Finalizer<_IntListToken>(
  (token) => secureZeroIntList(token.data, pattern: token.pattern),
);

/// A secure container for a [List<int>].
///
/// Use this for NTT polynomial coefficient arrays, intermediate ring
/// elements, and any secret integer data that must live as a general
/// integer list rather than a byte array.
///
/// Semantics mirror [SecretBytes] but for full Dart `int` values.
final class SecretIntList with Zeroizable implements Finalizable {
  List<int>? _data;
  final ZeroizePattern _pattern;
  bool _disposed = false;

  SecretIntList._(List<int> data, this._pattern) : _data = data {
    _intListFinalizer.attach(
      this,
      (data: data, pattern: _pattern),
      detach: this,
    );
  }

  // ─── Factories ─────────────────────────────────────────────────────────────

  /// Creates a [SecretIntList] filled with [fillValue] of length [length].
  factory SecretIntList.ofLength(
    int length, {
    int fillValue = 0,
    ZeroizePattern? pattern,
  }) =>
      SecretIntList._(
        List<int>.filled(length, fillValue, growable: false),
        pattern ?? ZeroizeConfig.defaultPattern,
      );

  /// Creates a [SecretIntList] by copying [source].
  factory SecretIntList.fromList(
    List<int> source, {
    ZeroizePattern? pattern,
  }) =>
      SecretIntList._(
        List<int>.of(source, growable: false),
        pattern ?? ZeroizeConfig.defaultPattern,
      );

  // ─── Properties ────────────────────────────────────────────────────────────

  /// Number of elements.
  int get length {
    _assertLive();
    return _data!.length;
  }

  /// Whether [dispose] has been called.
  bool get isDisposed => _disposed;

  // ─── Access ────────────────────────────────────────────────────────────────

  /// Read access.
  int operator [](int index) {
    _assertLive();
    return _data![index];
  }

  /// Write access.
  void operator []=(int index, int value) {
    _assertLive();
    _data![index] = value;
  }

  /// Provides a **read-only** window. Do NOT retain [data] beyond [fn].
  T use<T>(T Function(List<int> data) fn) {
    _assertLive();
    return fn(_data!);
  }

  /// Provides a **read/write** window for in-place operations.
  T mutate<T>(T Function(List<int> data) fn) {
    _assertLive();
    return fn(_data!);
  }

  /// Fills every element with [value].
  void fill(int value) {
    _assertLive();
    _data!.fillRange(0, _data!.length, value);
  }

  // ─── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void zeroize() => dispose();

  /// Securely zeroes and releases the backing list.
  ///
  /// Safe to call multiple times — subsequent calls are no-ops.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    final data = _data;
    _data = null;
    _intListFinalizer.detach(this);
    if (data != null) secureZeroIntList(data, pattern: _pattern);
  }

  void _assertLive() {
    if (_disposed) throw ZeroizeDisposedError('SecretIntList');
  }

  @override
  String toString() => _disposed
      ? 'SecretIntList(disposed)'
      : 'SecretIntList(${_data?.length} elements)';
}
