import '../errors.dart';
import '../lifecycle/zeroizable.dart';

/// A generic opaque container for any secret value of type [T].
///
/// The caller provides [zeroCallback] — a closure that defines how to zero
/// [T].  This gives full flexibility for custom types that [SecretBytes]
/// cannot cover directly.
///
/// ```dart
/// final box = SecretBox<MyKey>(
///   MyKey.generate(),
///   (key) => key.dispose(),
/// );
///
/// final sig = box.use((key) => sign(message, key));
/// box.dispose();
/// ```
///
/// For [Uint8List]-backed secrets, prefer [SecretBytes] which adds
/// [Finalizer] and [ZeroizePattern] support.
final class SecretBox<T> with Zeroizable {
  T? _value;
  final void Function(T value) _zeroCallback;
  bool _disposed = false;

  /// Creates a [SecretBox] holding [value].
  ///
  /// [zeroCallback] is called with [value] exactly once, when [dispose] is
  /// first called (or when [zeroize] is called via a [ZeroizeScope]).
  SecretBox(T value, void Function(T value) zeroCallback)
      : _value = value,
        _zeroCallback = zeroCallback;

  /// Whether [dispose] has been called.
  bool get isDisposed => _disposed;

  // ─── Access ────────────────────────────────────────────────────────────────

  /// Read-only access window.
  ///
  /// **Do NOT store [value] beyond [fn]'s scope.**
  R use<R>(R Function(T value) fn) {
    _assertLive();
    return fn(_value as T);
  }

  /// Read/write access window.
  R mutate<R>(R Function(T value) fn) {
    _assertLive();
    return fn(_value as T);
  }

  // ─── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void zeroize() => dispose();

  /// Calls [zeroCallback] with the held value and marks the box as disposed.
  ///
  /// Safe to call multiple times — the callback is invoked at most once.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    final v = _value!;
    _value = null;
    _zeroCallback(v);
  }

  void _assertLive() {
    if (_disposed) throw ZeroizeDisposedError('SecretBox<$T>');
  }

  @override
  String toString() =>
      'SecretBox<$T>(${_disposed ? 'disposed' : 'live'})';
}
