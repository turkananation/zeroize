import '../errors.dart';
import 'zeroizable.dart';

/// A scope that tracks [Zeroizable] instances and zeroes all of them when
/// [dispose] is called.
///
/// Provides RAII-style lifetime management for multiple secrets.  Secrets
/// are zeroed in **LIFO order** (last registered = first zeroed), mirroring
/// natural construction/destruction order for derived material.
///
/// ```dart
/// final result = await ZeroizeScope.runAsync((scope) async {
///   final dk = scope.track(await kdf.derive(inputKey));
///   final ek = scope.track(await kem.encapsulate(peerPk));
///   return await handshake(dk, ek);
/// }); // dk and ek are zeroed here — even if handshake threw
/// ```
final class ZeroizeScope {
  final List<Zeroizable> _tracked = [];
  bool _disposed = false;

  /// Creates an empty [ZeroizeScope].
  ZeroizeScope();

  /// Whether [dispose] has been called.
  bool get isDisposed => _disposed;

  // ─── Tracking ─────────────────────────────────────────────────────────────

  /// Registers [item] for zeroing when this scope is disposed.
  ///
  /// Returns [item] unchanged for fluent inline use:
  /// ```dart
  /// final key = scope.track(SecretBytes.fromList(raw));
  /// ```
  ///
  /// Throws [ZeroizeContractError] if called on an already-disposed scope;
  /// [item] is zeroed immediately in that case to prevent leaks.
  T track<T extends Zeroizable>(T item) {
    if (_disposed) {
      item.zeroize();
      throw ZeroizeContractError(
        'track() called on a disposed ZeroizeScope — '
        'item was zeroed immediately to prevent a leak',
      );
    }
    _tracked.add(item);
    return item;
  }

  // ─── Disposal ─────────────────────────────────────────────────────────────

  /// Zeroes all tracked instances in LIFO order.
  ///
  /// Safe to call multiple times — subsequent calls are no-ops.
  /// Individual zeroize failures are caught so every secret is attempted.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (var i = _tracked.length - 1; i >= 0; i--) {
      try {
        _tracked[i].zeroize();
      } catch (_) {
        // One failure must not prevent others from being zeroed.
      }
    }
    _tracked.clear();
  }

  // ─── Static factory runners ───────────────────────────────────────────────

  /// Runs [fn] synchronously with a fresh [ZeroizeScope].
  ///
  /// The scope is disposed after [fn] returns or throws.
  static T run<T>(T Function(ZeroizeScope scope) fn) {
    final scope = ZeroizeScope();
    try {
      return fn(scope);
    } finally {
      scope.dispose();
    }
  }

  /// Runs [fn] asynchronously with a fresh [ZeroizeScope].
  ///
  /// The scope is disposed after [fn] completes or throws.
  static Future<T> runAsync<T>(
    Future<T> Function(ZeroizeScope scope) fn,
  ) async {
    final scope = ZeroizeScope();
    try {
      return await fn(scope);
    } finally {
      scope.dispose();
    }
  }
}
