/// Thrown when a secure container is accessed after [dispose]/[zeroize].
///
/// Treat this as a programming error — equivalent to [StateError].
final class ZeroizeDisposedError extends Error {
  final String objectType;

  ZeroizeDisposedError(this.objectType);

  @override
  String toString() =>
      'ZeroizeDisposedError: $objectType was used after disposal. '
      'Ensure zeroize()/dispose() is called exactly once at end-of-life.';
}

/// Thrown when a zeroize contract is violated — e.g. sealing a
/// [SecretBuffer] twice, or tracking into a disposed [ZeroizeScope].
final class ZeroizeContractError extends Error {
  final String message;

  ZeroizeContractError(this.message);

  @override
  String toString() => 'ZeroizeContractError: $message';
}
