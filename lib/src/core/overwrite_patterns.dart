/// Byte overwrite strategy used during secure zeroing.
///
/// Every pattern ends with a `dseOpaqueRead` or `dseOpaqueReadFold` call
/// after each pass to anchor the writes in the compiler's dependency graph
/// and prevent Dead Store Elimination.
///
/// ### Choosing a pattern
///
/// | Pattern          | Passes | Use case                                      |
/// |------------------|--------|-----------------------------------------------|
/// | [zero]           | 1      | NIST SP 800-88 Rev 1 — single DRAM pass       |
/// | [ones]           | 1      | Single complement baseline                    |
/// | [twoPass]        | 2      | **Default** — strong DSE resistance           |
/// | [dod]            | 3      | DoD 5220.22-M adapted for volatile memory     |
/// | [pseudoRandom]   | 2      | Bit-pattern diversity + final zero            |
/// | [gutmann7]       | 7      | Maximum best-effort in pure Dart              |
///
/// > **Note:** Multiple passes on DRAM add DSE resistance and bit-pattern
/// > diversity — not demagnetisation protection (which applies only to
/// > magnetic media).  The Gutmann method's full 35-pass sequence targets
/// > older magnetic storage; [gutmann7] is a practical DRAM-adapted subset.
enum ZeroizePattern {
  /// Single pass: writes `0x00` to every byte.
  zero,

  /// Single pass: writes `0xFF` to every byte.
  ones,

  /// Two passes: `0xFF` then `0x00`.
  ///
  /// Ensures the final zero write is preceded by a meaningful non-zero
  /// write, making it non-dead from the optimiser's perspective.
  twoPass,

  /// Three passes: `0x00`, `0xFF`, `0x00`.
  ///
  /// Adapted from DoD 5220.22-M §8-306 for volatile memory.
  dod,

  /// Two passes: pseudo-random bytes, then `0x00`.
  ///
  /// Provides bit-pattern diversity while leaving memory in a known-zero
  /// state.  Uses the package's internal `PseudoRng` — not
  /// cryptographically secure.
  pseudoRandom,

  /// Seven passes: `0x00` · `0xFF` · `0xAA` · `0x55` · random · `0xFF`
  /// · `0x00`.
  ///
  /// DRAM-adapted subset of the Gutmann method.  Maximum best-effort
  /// zeroing available in pure Dart.
  gutmann7,
}
