import 'dart:typed_data';

import '../annotations/annotations.dart';
import '../core/dse_guard.dart';

/// Constant-time primitives for cryptographic use.
///
/// ## Platform Contract
///
/// These operations are constant-time at the **Dart source level** and in
/// **AOT release** builds on the Dart VM (x64, arm64).  They are **not**
/// constant-time in:
///
/// - Debug/profile builds — the JIT may speculate and reorder.
/// - Dart compiled to JavaScript — JS engines freely reorder and optimise.
/// - Dart compiled to Wasm — no CT guarantee from the Dart-to-Wasm compiler.
///
/// **Always deploy cryptographic code as AOT-compiled release binaries.**
///
/// ## Naming
///
/// All functions are prefixed `ct` to make their character explicit at
/// call sites and to aid code review.

// ─── Byte-sequence comparison ─────────────────────────────────────────────────

/// Compares [a] and [b] in constant time, scanning the full length of the
/// shorter buffer regardless of early differences.
///
/// Returns `0` iff both buffers have identical content **and** identical
/// length.  Returns a non-zero value otherwise.  The exact non-zero value
/// is implementation-defined — do NOT use it for ordering.
@constantTime
@pragma('vm:prefer-inline')
int ctCompareBytes(Uint8List a, Uint8List b) {
  final minLen = a.length < b.length ? a.length : b.length;
  // XOR-ing lengths makes a length mismatch contribute to the result
  // without short-circuiting.
  var diff = a.length ^ b.length;
  for (var i = 0; i < minLen; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff;
}

/// Returns `true` iff [a] and [b] are identical in length and content,
/// evaluated in constant time.
@constantTime
@pragma('vm:prefer-inline')
bool ctEquals(Uint8List a, Uint8List b) => ctCompareBytes(a, b) == 0;

/// CT comparison for [List<int>] (polynomial coefficient arrays, etc.).
@constantTime
@pragma('vm:prefer-inline')
int ctCompareIntLists(List<int> a, List<int> b) {
  final minLen = a.length < b.length ? a.length : b.length;
  var diff = a.length ^ b.length;
  for (var i = 0; i < minLen; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff;
}

/// Returns `true` iff [a] and [b] (as [List<int>]) are identical in CT.
@constantTime
@pragma('vm:prefer-inline')
bool ctEqualsIntLists(List<int> a, List<int> b) => ctCompareIntLists(a, b) == 0;

// ─── Authentication tag verification ─────────────────────────────────────────

/// Constant-time verification of two authentication tags.
///
/// Use this for **every** AEAD/MAC tag comparison.  Using `==` or
/// `ListEquality` creates a timing oracle that leaks the position of the
/// first differing byte.
///
/// When tags differ in length a dummy scan of [expected] still runs to
/// prevent a length-check fast-path from leaking timing information.
///
/// ```dart
/// if (!ctVerifyTag(computedTag, receivedTag)) {
///   throw AuthenticationException('AEAD tag mismatch');
/// }
/// ```
@constantTime
@pragma('vm:never-inline')
bool ctVerifyTag(Uint8List expected, Uint8List received) {
  if (expected.length != received.length) {
    var dummy = 0;
    for (var i = 0; i < expected.length; i++) {
      dummy |= expected[i];
    }
    dseObserve(dummy);
    return false;
  }
  var diff = 0;
  for (var i = 0; i < expected.length; i++) {
    diff |= expected[i] ^ received[i];
  }
  return diff == 0;
}

// ─── Integer selection ────────────────────────────────────────────────────────

/// Constant-time integer select.
///
/// Returns [ifOne] when [condition] == 1, [ifZero] when [condition] == 0.
/// [condition] MUST be exactly `0` or `1` — other values give undefined
/// results.
///
/// Implementation uses two's-complement arithmetic:
/// `-(1)` = all-ones mask; `-(0)` = all-zeros mask.
@constantTime
@pragma('vm:prefer-inline')
int ctSelect(int condition, int ifOne, int ifZero) {
  assert(
      condition == 0 || condition == 1, 'ctSelect: condition must be 0 or 1');
  final mask = -condition;
  return (mask & ifOne) | (~mask & ifZero);
}

/// Constant-time byte select; output masked to `[0, 255]`.
/// [condition] MUST be `0` or `1`.
@constantTime
@pragma('vm:prefer-inline')
int ctSelectByte(int condition, int ifOne, int ifZero) {
  final mask = (-condition) & 0xFF;
  return (mask & ifOne) | ((~mask) & 0xFF & ifZero);
}

// ─── Buffer operations ────────────────────────────────────────────────────────

/// Conditionally copies [src] into [dst] in constant time.
///
/// - condition == 1 → `dst = src`
/// - condition == 0 → `dst` unchanged
///
/// [condition] MUST be `0` or `1`.  [dst] and [src] MUST be the same length.
///
/// `vm:never-inline` prevents scalar replacement of [dst] which would allow
/// the optimiser to see through the write.
@constantTime
@pragma('vm:never-inline')
void ctConditionalCopy(int condition, Uint8List dst, Uint8List src) {
  assert(dst.length == src.length, 'ctConditionalCopy: length mismatch');
  assert(condition == 0 || condition == 1);
  final mask = (-condition) & 0xFF;
  final notMask = (~mask) & 0xFF;
  for (var i = 0; i < dst.length; i++) {
    dst[i] = (mask & src[i]) | (notMask & dst[i]);
  }
}

/// Conditionally swaps [a] and [b] element-wise in constant time.
///
/// - condition == 1 → swap
/// - condition == 0 → no change
///
/// [condition] MUST be `0` or `1`.  [a] and [b] MUST be the same length.
@constantTime
@pragma('vm:never-inline')
void ctConditionalSwap(int condition, Uint8List a, Uint8List b) {
  assert(a.length == b.length, 'ctConditionalSwap: length mismatch');
  assert(condition == 0 || condition == 1);
  final mask = (-condition) & 0xFF;
  for (var i = 0; i < a.length; i++) {
    final diff = mask & (a[i] ^ b[i]);
    a[i] ^= diff;
    b[i] ^= diff;
  }
}

// ─── Integer predicates ───────────────────────────────────────────────────────

/// Returns `1` if `a < b` (signed), `0` otherwise. Branchless.
///
/// Extracts the sign bit of `(a − b)` via arithmetic right shift by 62.
/// On the Dart VM (64-bit), integers are 63-bit Smis; the sign bit is at
/// position 62.
///
/// **Precondition:** `|a − b|` must not overflow the signed 62-bit range.
/// For polynomial coefficients (q < 2^24) this is always satisfied.
@constantTime
@pragma('vm:prefer-inline')
int ctLessThan(int a, int b) => ((a - b) >> 62) & 1;

/// Returns `1` if `a > b`, `0` otherwise. Branchless.
@constantTime
@pragma('vm:prefer-inline')
int ctGreaterThan(int a, int b) => ctLessThan(b, a);

/// Returns `1` if `a <= b`, `0` otherwise. Branchless.
@constantTime
@pragma('vm:prefer-inline')
int ctLessOrEqual(int a, int b) => 1 - ctGreaterThan(a, b);

/// Returns `1` if `a >= b`, `0` otherwise. Branchless.
@constantTime
@pragma('vm:prefer-inline')
int ctGreaterOrEqual(int a, int b) => 1 - ctLessThan(a, b);

/// Returns `1` if `a == b` (integers), `0` otherwise. Branchless.
///
/// For any non-zero `d`, `(-d | d)` has the sign bit (bit 62) set because
/// either `d` or `-d` is negative.  For `d == 0`, `(-d | d) == 0`.
/// Arithmetic right-shift by 62 fills with the sign bit, giving -1 (all
/// ones) for non-zero d, or 0 for zero d.
@constantTime
@pragma('vm:prefer-inline')
int ctIntEquals(int a, int b) {
  final d = a ^ b;
  // (-d | d) is negative iff d != 0.  Arithmetic shift fills sign into LSB.
  return 1 - (((d | -d) >> 62) & 1);
}

/// Returns `1` if `v == 0`, `0` otherwise.
@constantTime
@pragma('vm:prefer-inline')
int ctIsZero(int v) => ctIntEquals(v, 0);

/// Returns `1` if `v != 0`, `0` otherwise.
@constantTime
@pragma('vm:prefer-inline')
int ctIsNonZero(int v) => 1 - ctIsZero(v);

// ─── Integer arithmetic ───────────────────────────────────────────────────────

/// Branchless absolute value.
@constantTime
@pragma('vm:prefer-inline')
int ctAbs(int v) {
  final mask = v >> 62;
  return (v ^ mask) - mask;
}

/// Branchless clamp to `[min, max]`.
@constantTime
@pragma('vm:prefer-inline')
int ctClamp(int v, int min, int max) {
  final r = ctSelect(ctLessThan(v, min), min, v);
  return ctSelect(ctGreaterThan(r, max), max, r);
}

// ─── Modular arithmetic helpers ───────────────────────────────────────────────

/// Conditionally adds [mod] to [v] if [condition] == 1.
///
/// Lifts a value from a negative range into `[0, mod)` without branching.
/// [condition] MUST be `0` or `1`.
@constantTime
@pragma('vm:prefer-inline')
int ctConditionalAdd(int condition, int v, int mod) =>
    v + ctSelect(condition, mod, 0);

/// Conditionally subtracts [mod] from [v] if [condition] == 1.
///
/// Single CT modular reduction step when [v] is in `[0, 2*mod)`.
/// [condition] MUST be `0` or `1`.
@constantTime
@pragma('vm:prefer-inline')
int ctConditionalSub(int condition, int v, int mod) =>
    v - ctSelect(condition, mod, 0);

/// Reduces [v] into `[0, mod)` with a single conditional subtraction.
///
/// Requires [v] to be in `[0, 2*mod)`.
@constantTime
@pragma('vm:prefer-inline')
int ctReduceOnce(int v, int mod) =>
    ctConditionalSub(ctGreaterOrEqual(v, mod), v, mod);

/// Lifts [v] from `[-(mod-1), mod-1]` into `[0, mod)` with a single
/// conditional addition.
@constantTime
@pragma('vm:prefer-inline')
int ctLiftToPositive(int v, int mod) => ctConditionalAdd((v >> 62) & 1, v, mod);
