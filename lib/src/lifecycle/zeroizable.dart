/// Mixin for any class that holds sensitive material and must be explicitly
/// zeroed.
///
/// ## Contract
///
/// Implementing classes MUST:
/// - Override [zeroize] and zero every sensitive field ([SecretBytes],
///   [SecretIntList], [SecretBox], nested [Zeroizable] objects).
/// - Make [zeroize] **idempotent** — safe to call multiple times.
/// - Zero **before** throwing, not after: if construction fails partway
///   through, zero what was already allocated in the error path.
///
/// ```dart
/// final class MlKemPrivateKey with Zeroizable {
///   final SecretBytes _seed;
///   final SecretIntList _s; // private-key polynomial vector
///   bool _disposed = false;
///
///   @override
///   void zeroize() {
///     if (_disposed) return;
///     _disposed = true;
///     _seed.dispose();
///     _s.dispose();
///   }
/// }
/// ```
mixin Zeroizable {
  /// Zeroes all sensitive fields in this object.
  ///
  /// Must be idempotent — calling multiple times is safe and a no-op after
  /// the first call.
  void zeroize();

  /// Runs [fn] and unconditionally calls [zeroize] afterwards, even on throw.
  ///
  /// ```dart
  /// final ciphertext = privateKey.useAndZeroize(
  ///   () => kem.decapsulate(ct),
  /// );
  /// ```
  T useAndZeroize<T>(T Function() fn) {
    try {
      return fn();
    } finally {
      zeroize();
    }
  }

  /// Async variant of [useAndZeroize].
  Future<T> useAndZeroizeAsync<T>(Future<T> Function() fn) async {
    try {
      return await fn();
    } finally {
      zeroize();
    }
  }
}
