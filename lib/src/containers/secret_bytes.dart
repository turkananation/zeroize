import 'dart:typed_data';

import '../config/zeroize_config.dart';
import '../core/dse_guard.dart';
import '../core/overwrite_patterns.dart';
import '../core/secure_zero.dart';
import '../errors.dart';
import '../lifecycle/zeroizable.dart';

// ─── Finalizer setup ──────────────────────────────────────────────────────────

// Token: carries the backing buffer and zeroing pattern to the finalizer
// callback, which runs without access to the SecretBytes instance.
typedef _FinalizerToken = ({Uint8List data, ZeroizePattern pattern});

/// Package-level Finalizer kept alive for the entire isolate lifetime.
///
/// When a [SecretBytes] is GC'd without [dispose], this zeroes the backing
/// buffer.  GC-moved intermediate copies of that buffer may not be zeroed —
/// call [dispose] explicitly for deterministic cleanup.
final _finalizer = Finalizer<_FinalizerToken>(
  (token) => secureZero(token.data, pattern: token.pattern),
);

// ─── SecretBytes ──────────────────────────────────────────────────────────────

/// A secure byte container that zeroes its backing [Uint8List] on disposal.
///
/// ## Lifetime Pattern
///
/// ```dart
/// final key = SecretBytes.fromList(rawKeyBytes);
/// try {
///   final ciphertext = aeadEncrypt(key, nonce, plaintext);
///   return ciphertext;
/// } finally {
///   key.dispose(); // deterministic, multi-pass zeroing
/// }
/// ```
///
/// Or with [ZeroizeScope] for automatic management of multiple secrets:
///
/// ```dart
/// final result = await ZeroizeScope.runAsync((scope) async {
///   final sk = scope.track(SecretBytes.fromList(rawSk));
///   final ek = scope.track(SecretBytes.fromList(rawEk));
///   return await handshake(sk, ek);
/// }); // sk and ek are zeroed here
/// ```
///
/// ## Access Model
///
/// The backing [Uint8List] is **never returned directly**.  All access is
/// via [use] (read-only window) and [mutate] (read/write window).
///
/// **Never store the [Uint8List] argument outside [use]/[mutate]'s
/// callback.**  Retaining it defeats the disposal guarantee.
///
/// ## Memory-Safety Contract
///
/// - A copy of [source] is made on construction — caller's buffer is not
///   owned by this object.
/// - A [Finalizer] provides a last-resort zero if the object is GC'd
///   without [dispose].
/// - GC-copied intermediate buffers may not be zeroed — this is an
///   acknowledged limitation of pure Dart (see package README).
/// - Compile to AOT release for maximum DSE resistance.
final class SecretBytes with Zeroizable implements Finalizable {
  Uint8List? _data;
  final ZeroizePattern _pattern;
  bool _disposed = false;

  SecretBytes._(Uint8List data, this._pattern) : _data = data {
    _finalizer.attach(
      this,
      (data: data, pattern: _pattern),
      detach: this,
    );
    ZeroizeConfig.trackAllocate();
  }

  // ─── Factories ─────────────────────────────────────────────────────────────

  /// Creates a [SecretBytes] by copying [source].
  ///
  /// The caller retains ownership of [source] and must zero it separately
  /// if it also contains sensitive material.
  factory SecretBytes.fromList(
    List<int> source, {
    ZeroizePattern? pattern,
  }) =>
      SecretBytes._(
        Uint8List.fromList(source),
        pattern ?? ZeroizeConfig.defaultPattern,
      );

  /// Creates a [SecretBytes] by copying [source].
  factory SecretBytes.fromUint8List(
    Uint8List source, {
    ZeroizePattern? pattern,
  }) =>
      SecretBytes._(
        Uint8List.fromList(source), // always copy — never take ownership
        pattern ?? ZeroizeConfig.defaultPattern,
      );

  /// Creates a [SecretBytes] of [length] zero bytes.
  factory SecretBytes.ofLength(int length, {ZeroizePattern? pattern}) =>
      SecretBytes._(
        Uint8List(length),
        pattern ?? ZeroizeConfig.defaultPattern,
      );

  /// Creates a [SecretBytes] by generating each byte with [generator].
  ///
  /// Avoids a plain intermediate [List<int>] in the caller's scope.
  /// [generator] receives the byte index and MUST return a value in [0, 255].
  factory SecretBytes.generate(
    int length,
    int Function(int index) generator, {
    ZeroizePattern? pattern,
  }) {
    final data = Uint8List(length);
    for (var i = 0; i < length; i++) {
      data[i] = generator(i) & 0xFF;
    }
    return SecretBytes._(data, pattern ?? ZeroizeConfig.defaultPattern);
  }

  // ─── Properties ────────────────────────────────────────────────────────────

  /// Number of bytes held by this container.
  int get length {
    _assertLive();
    return _data!.length;
  }

  /// Whether [dispose] has been called.
  bool get isDisposed => _disposed;

  // ─── Access ────────────────────────────────────────────────────────────────

  /// Provides a **read-only** window into the backing buffer.
  ///
  /// **Do NOT store a reference to [bytes] beyond the scope of [fn].**
  /// Retaining it defeats the disposal guarantee entirely.
  T use<T>(T Function(Uint8List bytes) fn) {
    _assertLive();
    return fn(_data!);
  }

  /// Provides a **read/write** window into the backing buffer.
  ///
  /// Use for in-place operations: XOR masking, key schedule filling, etc.
  /// The same reference-retention warning as [use] applies.
  T mutate<T>(T Function(Uint8List bytes) fn) {
    _assertLive();
    return fn(_data!);
  }

  // ─── Operations ────────────────────────────────────────────────────────────

  /// XORs the backing buffer with [mask] in-place.
  ///
  /// [mask] MUST be the same length as this [SecretBytes].
  void xorWith(Uint8List mask) {
    _assertLive();
    final data = _data!;
    assert(data.length == mask.length, 'xorWith: length mismatch');
    for (var i = 0; i < data.length; i++) {
      data[i] ^= mask[i];
    }
  }

  /// Fills the entire backing buffer with [byte].
  void fill(int byte) {
    _assertLive();
    _data!.fillRange(0, _data!.length, byte & 0xFF);
  }

  /// Returns a new independent [SecretBytes] containing bytes [start]..[end].
  SecretBytes subrange(int start, [int? end]) {
    _assertLive();
    return SecretBytes.fromUint8List(
      _data!.sublist(start, end),
      pattern: _pattern,
    );
  }

  /// Returns a new [SecretBytes] that is the concatenation of [this] and
  /// [other].
  SecretBytes concat(SecretBytes other) {
    _assertLive();
    other._assertLive();
    final out = Uint8List(length + other.length);
    out.setRange(0, length, _data!);
    other.use((b) => out.setRange(length, out.length, b));
    return SecretBytes._(out, _pattern);
  }

  // ─── Constant-time comparison ─────────────────────────────────────────────

  /// Timing-safe equality against another [SecretBytes].
  bool timingSafeEquals(SecretBytes other) {
    _assertLive();
    other._assertLive();
    if (identical(this, other)) return true;
    return use((a) => other.use((b) {
          if (a.length != b.length) {
            // Scan anyway to avoid length-difference fast-path oracle.
            var dummy = 0;
            for (var i = 0; i < a.length; i++) {
              dummy |= a[i];
            }
            dseObserve(dummy);
            return false;
          }
          var diff = 0;
          for (var i = 0; i < a.length; i++) {
            diff |= a[i] ^ b[i];
          }
          return diff == 0;
        }));
  }

  /// Timing-safe equality against a plain [Uint8List].
  bool timingSafeEqualsBytes(Uint8List other) {
    _assertLive();
    return use((a) {
      if (a.length != other.length) {
        var dummy = 0;
        for (var i = 0; i < a.length; i++) {
          dummy |= a[i];
        }
        dseObserve(dummy);
        return false;
      }
      var diff = 0;
      for (var i = 0; i < a.length; i++) {
        diff |= a[i] ^ other[i];
      }
      return diff == 0;
    });
  }

  // ─── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void zeroize() => dispose();

  /// Securely zeroes and releases the backing buffer.
  ///
  /// Safe to call multiple times — subsequent calls are no-ops.
  /// After disposal [use], [mutate], and [length] throw [ZeroizeDisposedError].
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    final data = _data;
    _data = null;
    _finalizer.detach(this);
    ZeroizeConfig.trackDispose();
    if (data != null) secureZero(data, pattern: _pattern);
  }

  void _assertLive() {
    if (_disposed) throw ZeroizeDisposedError('SecretBytes');
  }

  @override
  String toString() => _disposed
      ? 'SecretBytes(disposed)'
      : 'SecretBytes(${_data?.length ?? 0} bytes)';
}
