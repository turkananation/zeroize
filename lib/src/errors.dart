/// Thrown when a secure container is accessed after `dispose`/`zeroize`.
///
/// Treat this as a programming error — equivalent to [StateError].
final class ZeroizeDisposedError extends Error {
  /// The type or name of the object that was accessed after disposal.
  final String objectType;

  /// Creates a [ZeroizeDisposedError] for the given [objectType].
  ZeroizeDisposedError(this.objectType);

  @override
  String toString() =>
      'ZeroizeDisposedError: $objectType was used after disposal. '
      'Ensure zeroize()/dispose() is called exactly once at end-of-life.';
}

/// Thrown when a zeroize contract is violated — e.g. sealing a
/// [SecretBuffer] twice, or tracking into a disposed [ZeroizeScope].
final class ZeroizeContractError extends Error {
  /// Description of the contract violation.
  final String message;

  /// Creates a [ZeroizeContractError] with the specified [message].
  ZeroizeContractError(this.message);

  @override
  String toString() => 'ZeroizeContractError: $message';
}
