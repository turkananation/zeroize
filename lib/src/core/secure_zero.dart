import 'dart:typed_data';

import '../config/zeroize_config.dart';
import '../core/overwrite_patterns.dart';
import '../utils/pseudo_rng.dart';
import 'dse_guard.dart';

// ─── Internal single-pass writers ─────────────────────────────────────────────

/// Writes [byte] to every element of [data].
///
/// `vm:never-inline` prevents the compiler from inlining and then treating
/// the loop as dead.
@pragma('vm:never-inline')
void _fillConst(List<int> data, int byte) {
  for (var i = 0; i < data.length; i++) {
    data[i] = byte;
  }
}

/// Fills [data] with pseudo-random bytes from the package singleton PRNG.
@pragma('vm:never-inline')
void _fillRandom(List<int> data) => sharedPrng.fillBytes(data);

// ─── Public API ───────────────────────────────────────────────────────────────

/// Overwrites every byte of [data] using [pattern].
///
/// Between each pass an opaque read anchors the writes in the optimiser's
/// dependency graph, defeating Dead Store Elimination.
///
/// **Does not** guarantee that GC-moved copies of [data] are zeroed.
/// Use [SecretBytes] for a [Finalizer]-backed backstop.
///
/// ```dart
/// final tmp = Uint8List.fromList(rawKey);
/// try {
///   doWork(tmp);
/// } finally {
///   secureZero(tmp); // default twoPass pattern
/// }
/// ```
@pragma('vm:never-inline')
void secureZero(Uint8List data, {ZeroizePattern? pattern}) {
  if (data.isEmpty) return;
  _applyPattern(data, pattern ?? ZeroizeConfig.defaultPattern);
}

/// Overwrites every element of [data] using [pattern].
///
/// Functionally identical to [secureZero] but accepts a general [List<int>],
/// which is the natural representation for NTT polynomial coefficients.
@pragma('vm:never-inline')
void secureZeroIntList(List<int> data, {ZeroizePattern? pattern}) {
  if (data.isEmpty) return;
  _applyPattern(data, pattern ?? ZeroizeConfig.defaultPattern);
}

/// Zeroes a sub-region of [data] from [offset] for [count] bytes.
///
/// Bytes outside `[offset, offset + count)` are untouched.
/// Zeroing is applied only to the view — the underlying buffer is shared.
@pragma('vm:never-inline')
void secureZeroRange(
  Uint8List data,
  int offset,
  int count, {
  ZeroizePattern? pattern,
}) {
  if (count <= 0) return;
  assert(
    offset >= 0 && offset + count <= data.length,
    'secureZeroRange: range [$offset, ${offset + count}) '
    'out of bounds for length ${data.length}',
  );
  final view = Uint8List.sublistView(data, offset, offset + count);
  secureZero(view, pattern: pattern);
}

// ─── Pattern dispatcher ───────────────────────────────────────────────────────

void _applyPattern(List<int> data, ZeroizePattern pattern) {
  final last = data.length - 1;

  switch (pattern) {
    case ZeroizePattern.zero:
      _fillConst(data, 0x00);
      dseOpaqueRead(data, last);

    case ZeroizePattern.ones:
      _fillConst(data, 0xFF);
      dseOpaqueRead(data, last);

    case ZeroizePattern.twoPass:
      _fillConst(data, 0xFF);
      dseOpaqueReadFold(data, last);
      _fillConst(data, 0x00);
      dseOpaqueRead(data, last);

    case ZeroizePattern.dod:
      _fillConst(data, 0x00);
      dseOpaqueReadFold(data, last);
      _fillConst(data, 0xFF);
      dseOpaqueReadFold(data, last);
      _fillConst(data, 0x00);
      dseOpaqueRead(data, last);

    case ZeroizePattern.pseudoRandom:
      _fillRandom(data);
      dseOpaqueReadFold(data, last);
      _fillConst(data, 0x00);
      dseOpaqueRead(data, last);

    case ZeroizePattern.gutmann7:
      // Pass 1: zero baseline
      _fillConst(data, 0x00);
      dseOpaqueReadFold(data, last);
      // Pass 2: complement
      _fillConst(data, 0xFF);
      dseOpaqueReadFold(data, last);
      // Pass 3: 0xAA = 10101010
      _fillConst(data, 0xAA);
      dseOpaqueReadFold(data, last);
      // Pass 4: 0x55 = 01010101 (complement of 0xAA)
      _fillConst(data, 0x55);
      dseOpaqueReadFold(data, last);
      // Pass 5: pseudo-random diversity
      _fillRandom(data);
      dseOpaqueReadFold(data, last);
      // Pass 6: pre-final complement
      _fillConst(data, 0xFF);
      dseOpaqueReadFold(data, last);
      // Pass 7: final zero — memory left in known clean state
      _fillConst(data, 0x00);
      dseOpaqueRead(data, last);
  }
}
