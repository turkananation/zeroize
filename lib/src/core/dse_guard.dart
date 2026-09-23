/// DSE (Dead Store Elimination) guard for the zeroize package.
///
/// The Dart AOT compiler can prove a write is never read and eliminate it
/// entirely. This file provides the mechanism to defeat that optimisation.
///
/// ## Mechanism
///
/// [_dseOpaqueSink] is a mutable package-level variable.  Because it is
/// reachable from outside the current compilation unit the compiler must
/// assume its value matters.  The `@pragma('vm:never-inline')` functions
/// below read through the pointer that was just written, establishing a
/// happens-before relationship the optimiser cannot break.
///
/// Result: writes to a buffer immediately before a call to [dseOpaqueRead]
/// or [dseOpaqueReadFold] cannot be classified as dead stores.

// Initialised to a non-zero 32-bit value so the compiler cannot
// constant-fold the XOR chain to a no-op, and the value stays within
// the Dart VM's Smi range on all 64-bit platforms.
int _dseOpaqueSink = 0x5A5A5A5A;

/// Reads [data\[idx\]] into [_dseOpaqueSink].
///
/// Preceding writes to [data] cannot be eliminated as dead stores because
/// this — a non-inlineable function — observably reads through the same
/// pointer after them.
///
/// MUST remain `vm:never-inline`.  Inlining would let the optimiser see
/// through the body and potentially remove the prior writes.
@pragma('vm:never-inline')
void dseOpaqueRead(List<int> data, int idx) {
  _dseOpaqueSink ^= data[idx];
}

/// Like [dseOpaqueRead] but also rotates the sink between passes.
///
/// A rotation prevents the compiler from treating two successive
/// XOR-into-sink operations as mutually cancelling (0 ^ x ^ x == 0),
/// which would allow it to treat both as dead.  Use between overwrite
/// passes of multi-pass patterns.
@pragma('vm:never-inline')
void dseOpaqueReadFold(List<int> data, int idx) {
  _dseOpaqueSink ^= data[idx];
  // 32-bit rotate-left by 1. Keeps the value within 32 bits (a Smi on all
  // 64-bit Dart VM configurations) and prevents the optimizer from treating
  // two successive XOR-into-sink operations as mutually cancelling.
  final s = _dseOpaqueSink & 0xFFFFFFFF;
  _dseOpaqueSink = ((s << 1) & 0xFFFFFFFF) | (s >>> 31);
}

/// Forces [value] to be observable without exposing it.
///
/// Use after computing a sensitive intermediate that must not be
/// eliminated as a dead computation.
@pragma('vm:never-inline')
void dseObserve(int value) {
  _dseOpaqueSink ^= value;
}
