# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased]

## [0.2.0] — 2026-10-08

### Added

#### Isolate transfer

- `SecretTransfer` — a **sendable** handle for secret bytes that must cross an
  isolate boundary. `SecretBytes` cannot be sent: it holds a `Finalizer` token and
  a non-sendable buffer, so `Isolate.run` and `SendPort` reject it. Previously the
  only portable option was a bare `Uint8List` wiped by hand on both sides.
  - `SecretTransfer.fromBytes(Uint8List)` — copies into the transferable buffer
    and zeroes the source immediately.
  - `materializeSecret()` — moves into a new `SecretBytes`, zeroing the
    materialized buffer in a `finally`.
  - `materializeBytes()` — moves into a bare `Uint8List` for APIs that require
    one (`PointyCastle`, `package:cryptography`). Caller owns and must wipe it.
  - `moveInto(SecretBytes)` — moves directly into an existing container; throws
    `ZeroizeContractError` if the target is too small, and wipes the transferred
    buffer either way.
  - `length`, `isConsumed`.
- `SecretBytes.intoTransfer()` — moves this container's bytes into a transfer and
  zeroes/disposes the source, so exactly one live copy exists afterwards.

### Notes

- `SecretTransfer` is **not** a memory-erasure guarantee. The buffer inside
  `TransferableTypedData` is runtime-managed and cannot be overwritten from Dart;
  the GC may still copy any `Uint8List` before it is zeroed; and pure Dart has no
  `mlock`. These are the same limits as the rest of the package and are stated in
  the class documentation.
- Single-consumption is **per isolate copy**, not global. Isolates do not share
  object state, so sending one transfer to two isolates yields two consumable
  copies. Send a transfer to exactly one receiver.
- Zero dependencies added. `package:meta` remains the only runtime dependency and
  no `dart:ffi` or `dart:io` was introduced.

---

## [0.1.0] — 2026-09-23

### Added

#### Core Zeroing Engine

- `secureZero(Uint8List)` — multi-pass secure zeroing with `ZeroizePattern` selection
- `secureZeroIntList(List<int>)` — zeroing for NTT polynomial coefficient arrays
- `secureZeroRange(Uint8List, offset, count)` — sub-region zeroing via `Uint8List.sublistView`
- `ZeroizePattern` enum — `zero`, `ones`, `twoPass` (default), `dod`, `pseudoRandom`, `gutmann7`

#### DSE Guard

- `_dseOpaqueSink` — mutable package-level variable that defeats Dead Store Elimination
- `dseOpaqueRead(List<int>, idx)` — `@pragma('vm:never-inline')` read after overwrite pass
- `dseOpaqueReadFold(List<int>, idx)` — read + 32-bit rotate-left mixing between passes
- `dseObserve(int)` — forces an intermediate value to be observable
- All DSE-guard values kept within 32-bit Smi range to avoid Mint/BigInt promotion

#### Containers

- `SecretBytes` — primary secret container
  - Factories: `fromList`, `fromUint8List`, `ofLength`, `generate`
  - Access: `use(fn)`, `mutate(fn)` (never exposes backing buffer directly)
  - Operations: `xorWith`, `fill`, `subrange`, `concat`
  - CT comparison: `timingSafeEquals`, `timingSafeEqualsBytes`
  - `Finalizer<_FinalizerToken>` for GC-triggered backstop zeroing
  - `ZeroizeConfig.trackAllocate/trackDispose` for debug leak detection

- `SecretIntList` — `List<int>` container for NTT polynomial arrays
  - Factories: `ofLength`, `fromList`
  - Access: `[]`, `[]=`, `use(fn)`, `mutate(fn)`
  - `Finalizer` for GC-triggered backstop zeroing

- `SecretBuffer` — incremental secret accumulator
  - `addByte`, `addBytes`, `addList`, `addFill`
  - Internal growth zeroes the old `Uint8List` allocation before release
  - `seal()` atomically transfers to `SecretBytes` and disposes buffer

- `SecretBox<T>` — generic opaque wrapper with caller-supplied zero callback

- `PasswordInput` — Dart `String`-aware password handler
  - `toUtf8SecretBytes()` — UTF-8 byte representation (zeroable)
  - `toCodePointsBytes()` — big-endian 32-bit code-point encoding (zeroable)
  - Documents the byte-collection alternative via `SecretBuffer`

#### Lifecycle Management

- `Zeroizable` mixin — `zeroize()`, `useAndZeroize(fn)`, `useAndZeroizeAsync(fn)`
- `ZeroizeScope` — RAII scope with LIFO disposal order
  - `track<T extends Zeroizable>(item)` — registers for zeroing
  - `run(fn)` / `runAsync(fn)` — factory runners with guaranteed disposal
- `withZeroizedBytes(Uint8List, fn)` / `withZeroizedBytesAsync` — scoped raw buffer zeroing
- `withZeroized(List<Zeroizable>, fn)` / `withZeroizedAsync` — LIFO multi-secret guard

#### Constant-Time Primitives

- Byte comparison: `ctCompareBytes`, `ctEquals`, `ctCompareIntLists`, `ctEqualsIntLists`
- Tag verification: `ctVerifyTag` — with length-mismatch dummy scan
- Integer selection: `ctSelect`, `ctSelectByte`
- Buffer ops: `ctConditionalCopy`, `ctConditionalSwap`
- Predicates: `ctLessThan`, `ctGreaterThan`, `ctLessOrEqual`, `ctGreaterOrEqual`, `ctIntEquals`, `ctIsZero`, `ctIsNonZero`
- Arithmetic: `ctAbs`, `ctClamp`
- Modular: `ctReduceOnce`, `ctLiftToPositive`, `ctConditionalAdd`, `ctConditionalSub`

#### Extensions

- `Uint8ListZeroize` — `.secureZeroize()`, `.xorWith()`, `.isAllZero`, `.toHexString()`
- `ListIntZeroize` — `.secureZeroize()`

#### Configuration & Annotations

- `ZeroizeConfig` — `defaultPattern`, `setDefaultPattern`, `liveSecretCount`,
  `totalAllocated`, `debugAssertNoLeaks()`
- `@sensitive` / `@constantTime` annotations
- `ZeroizeDisposedError` / `ZeroizeContractError` — typed error hierarchy

#### Utilities

- `PseudoRng` — Xorshift32 PRNG for overwrite pattern diversity (non-cryptographic)
- 60+ unit tests across all components

#### Documentation

- `doc/ARCHITECTURE.md` — layer-by-layer design rationale
- `doc/SECURITY_MODEL.md` — threat model, mitigations, and known limitations
- `doc/FEATURES.md` — complete feature catalogue
- `doc/ROADMAP.md` — planned versions and future directions
- `doc/API_GUIDE.md` — usage guide with realistic examples
- `doc/INTEGRATION.md` — integration patterns for `pqcrypto`, `pqforge`, `pqtransport`
- `doc/CONTRIBUTING.md` — contribution process and safety rules

[Unreleased]: https://github.com/turkananation/zeroize/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/turkananation/zeroize/releases/tag/v0.1.0
