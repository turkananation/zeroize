/// Non-cryptographic 32-bit Xorshift PRNG.
///
/// Used **exclusively** for generating byte overwrite patterns to provide
/// bit-pattern diversity during multi-pass secure zeroing.
///
/// DO NOT use for cryptographic key material, nonces, IVs, or any
/// security-sensitive random number generation.
///
/// All state is kept within 32 bits so bit shifts behave identically on
/// the Dart VM (63-bit int) and compiled-to-JS targets.
final class PseudoRng {
  // Always in [1, 0xFFFFFFFF] — xorshift32 must never be zero.
  int _state;

  /// Creates a PRNG seeded with [seed]. A seed of zero is replaced with a
  /// default non-zero constant.
  PseudoRng(int seed)
      : _state =
            (seed & 0xFFFFFFFF) == 0 ? 0x5A5A5A5A : (seed & 0xFFFFFFFF);

  /// Creates a PRNG seeded from the current microsecond timestamp mixed
  /// with a fixed constant. Non-deterministic across calls.
  factory PseudoRng.fromTimestamp() {
    final t = DateTime.now().microsecondsSinceEpoch;
    final s = ((t ^ (t >> 16)) ^ 0x5A5A5A5A) & 0xFFFFFFFF;
    return PseudoRng(s == 0 ? 0x5A5A5A5A : s);
  }

  /// Returns the next 32-bit pseudo-random integer (Xorshift32).
  int nextInt() {
    _state ^= (_state << 13) & 0xFFFFFFFF;
    _state ^= _state >> 17;
    _state ^= (_state << 5) & 0xFFFFFFFF;
    _state &= 0xFFFFFFFF;
    return _state;
  }

  /// Returns the next pseudo-random byte (0–255).
  int nextByte() => nextInt() & 0xFF;

  /// Fills [buf] with pseudo-random bytes.
  void fillBytes(List<int> buf) {
    for (var i = 0; i < buf.length; i++) {
      buf[i] = nextByte();
    }
  }
}

/// Package-internal singleton PRNG for overwrite patterns.
/// Re-seeded on isolate startup via the timestamp factory.
final sharedPrng = PseudoRng.fromTimestamp();
