# Roadmap

## v0.1.0 — Foundation (Current)

- Multi-pass secure zeroing (`secureZero`, `secureZeroIntList`, `secureZeroRange`)
- Full `ZeroizePattern` suite (zero, ones, twoPass, dod, pseudoRandom, gutmann7)
- DSE guard (`dse_guard.dart`) with `@pragma('vm:never-inline')` mechanism
- `SecretBytes` — primary container with `Finalizer`, `ZeroizePattern`, CT ops
- `SecretIntList` — NTT polynomial coefficient container
- `SecretBuffer` — incremental secret accumulator with resize-zeroing
- `SecretBox<T>` — generic opaque wrapper
- `PasswordInput` — String-limitation-aware password handler
- `ZeroizeScope` — RAII scope with LIFO disposal
- `withZeroized*` / `withZeroizedBytes*` guard functions
- `Zeroizable` mixin with `useAndZeroize` / `useAndZeroizeAsync`
- Full constant-time primitive suite (compare, select, conditional copy/swap,
  predicates, modular arithmetic)
- `Uint8ListZeroize` / `ListIntZeroize` extension methods
- `ZeroizeConfig` with global pattern and debug leak tracking
- `@sensitive` / `@constantTime` annotations
- 60+ unit tests across all components

---

## v0.2.0 — Hardening & Ergonomics (Planned)

### Timing Verification Tooling
- `TimingProbe` utility: wraps a function and samples wall-clock
  distribution to detect statistical CT violations in test environments.
- Integration with `dart test` for automated CT regression detection.

### Isolate Utilities (opt-in)
- Ship `package:zeroize/isolate.dart` as a separate entry point for
  `dart:isolate`-based crypto heap isolation.
- `runInCryptoIsolate<T>()` — runs computation in a short-lived isolate
  whose heap is discarded on exit.
- Platform detection so web builds fail at compile time rather than runtime.

### Enhanced `SecretBuffer`
- `SecretBuffer.fromStream(Stream<List<int>>)` — async streaming fill.
- `addSecretBytes(SecretBytes)` — zero-copy append from another container.

### `SecretInt32List` / `SecretInt64List`
- Typed-array variants backed by `Int32List` / `Int64List` for tighter
  integration with SIMD-friendly NTT implementations.

### `SecretView`
- A read-only window onto a sub-region of `SecretBytes` without copying.
- Useful for zero-copy key schedule derivation.

---

## v0.3.0 — Advanced CT Primitives (Planned)

### Modular Arithmetic Expansion
- Barrett reduction for arbitrary moduli (parameterised).
- Montgomery multiplication helpers for ML-KEM (q = 3329) and
  ML-DSA (q = 8380417).
- NTT butterfly operation (`fqmul`) in CT form.

### Bitsliced Operations
- CT bitwise operations on 64-bit words for symmetric cipher primitives.
- Suitable for pure-Dart AES bitsliced implementation.

### Constant-Time Table Lookup
- `ctLookup(table, index)` — oblivious array access via linear scan.
- Required for S-box operations without timing leaks.

---

## v0.4.0 — Platform Hardening (Planned)

### Conditional FFI Layer
- `package:zeroize/ffi.dart` — optional entry point when `dart:ffi` is
  available (Dart native, Flutter mobile/desktop).
- Uses `calloc` + `mlock` for OS-pinned secret pages.
- Provides `SecureAlloc` that bypasses the Dart GC entirely.
- Falls back gracefully to pure-Dart implementation on unsupported platforms.

### Wasm Compatibility Module
- Investigates Wasm linear-memory access patterns for CT guarantees.
- Documents which operations are CT in the Wasm MVP instruction set.

---

## v1.0.0 — Stable API (Target)

- API stability commitment.
- Security audit by external party.
- Formal documentation of CT guarantees per platform/compiler version.
- Integration test suite against pqcrypto / pqforge / pqtransport.
- FIPS 140-3 boundary documentation (informational, not certified).

---

## Long-Term Investigations

- **Dart VM `vm:volatile` pragma** — track the VM team's roadmap for a
  first-class volatile write primitive equivalent to Rust's `ptr::write_volatile`.
- **Wasm SIMD** — evaluate whether Wasm SIMD instructions introduce CT
  guarantees for our use cases.
- **Custom VM embedder** — investigate embedding the Dart VM with a custom
  GC policy that pins `SecretBytes` pages and prevents copying.

---

## Not Planned

- Full Gutmann 35-pass pattern — impractical on DRAM, adds no security value
  over `gutmann7` for volatile memory.
- Native Windows `CryptProtectMemory` / `SecureZeroMemory` — out of scope
  without FFI and not cross-platform.
- Automatic audit logging — use your application's logging layer.
