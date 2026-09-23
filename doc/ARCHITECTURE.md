# Architecture

## Overview

`zeroize` is a pure-Dart library with zero runtime dependencies (beyond
`meta` for annotations). It is organised into five logical layers, each
building on the one below.

```
┌──────────────────────────────────────────────────────┐
│  Public API Layer                                    │
│  SecretBytes · SecretIntList · SecretBuffer          │
│  SecretBox · PasswordInput · ZeroizeScope            │
│  withZeroized · ZeroizeGuard                         │
├──────────────────────────────────────────────────────┤
│  Constant-Time Layer  (ct_ops.dart)                  │
│  ctEquals · ctVerifyTag · ctSelect · ctConditional*  │
│  ctLessThan · ctAbs · ctReduceOnce · ctLiftTo*       │
├──────────────────────────────────────────────────────┤
│  Zeroing Engine  (secure_zero.dart)                  │
│  secureZero · secureZeroIntList · secureZeroRange    │
│  ZeroizePattern (zero/ones/twoPass/dod/random/guttmann7)│
├──────────────────────────────────────────────────────┤
│  DSE Guard  (dse_guard.dart)                         │
│  _dseOpaqueSink · dseOpaqueRead · dseOpaqueReadFold  │
│  dseObserve                                          │
├──────────────────────────────────────────────────────┤
│  Support                                             │
│  PseudoRng (Xorshift32) · ZeroizeConfig              │
│  Annotations (@sensitive, @constantTime)             │
└──────────────────────────────────────────────────────┘
```

---

## Layer 1: DSE Guard (`src/core/dse_guard.dart`)

### Problem

The Dart AOT compiler performs Dead Store Elimination (DSE): if a write
to a memory location is never subsequently read, the write is removed.
This is catastrophically unsafe for zeroing — the compiler proves that
the zero write is never read and removes it entirely.

### Mechanism

A package-level mutable variable `_dseOpaqueSink` is maintained.
The functions `dseOpaqueRead` and `dseOpaqueReadFold` are annotated
`@pragma('vm:never-inline')`, which prevents the AOT compiler from
inlining them and seeing through their bodies.

Because these functions observably read through the same `List<int>`
that was just written, the compiler must establish a happens-before
edge: *the writes must occur before the non-inlineable read*. DSE is
therefore prevented.

```
Write to data[i]  →  dseOpaqueRead(data, last)  →  _dseOpaqueSink changes
     ↑                       ↑
  Cannot be              Cannot be
  eliminated             inlined
```

### `dseOpaqueReadFold` — multi-pass protection

Between overwrite passes a simple rotation of `_dseOpaqueSink` prevents
the optimizer treating two XOR-into-sink operations as mutually
cancelling (`a ^ b ^ a ^ b == 0`). A 32-bit rotate-left by 1 is used
to keep the sink value within the Dart VM's Smi range on all 64-bit
platforms.

---

## Layer 2: Zeroing Engine (`src/core/secure_zero.dart`)

Dispatches to a set of `@pragma('vm:never-inline')` single-pass writers
(`_fillConst`, `_fillRandom`) through the `ZeroizePattern` enum.

Each pattern interleaves writes with DSE-guard reads, ensuring:
- The writes are observable to the compiler.
- The final state of the buffer is always zero.
- Multiple passes provide bit-pattern diversity against memory remanence.

The `secureZeroRange` helper operates on a `Uint8List.sublistView`, which
shares the underlying `ByteBuffer`, so writes to the view zero the
corresponding bytes in the original.

---

## Layer 3: Constant-Time Layer (`src/ct/ct_ops.dart`)

Implements the standard branchless techniques:

| Technique | Implementation |
|-----------|---------------|
| CT compare | XOR accumulator scanned full length |
| CT select | Two's-complement mask: `-(condition)` |
| CT conditional copy | Byte-level: `(mask & src[i]) \| (notMask & dst[i])` |
| CT conditional swap | Delta encoding: `diff = mask & (a[i] ^ b[i])` |
| CT less-than | Sign-bit extraction via arithmetic right-shift by 62 |
| CT integer equality | `(-d \| d) >> 62` sign-bit test |
| CT abs | Arithmetic-shift mask: `(v ^ mask) - mask` |
| CT modular reduction | Single conditional subtract/add |

All functions are `@pragma('vm:prefer-inline')` to eliminate call overhead
while keeping operations visible to the optimizer as typed integer ops —
which are emitted as single-cycle instructions on x64/arm64.

### Platform Contract

| Build | CT? | Notes |
|-------|-----|-------|
| AOT release | ✓ Source-level CT | Primary target |
| JIT debug/profile | ✗ | JIT may speculate |
| JS | ✗ | JS engine rewrites freely |
| Wasm | ✗ | No CT guarantee |

---

## Layer 4: Containers (`src/containers/`)

### `SecretBytes`

- Holds a `Uint8List` — never exposed directly, only via `use`/`mutate` callbacks.
- Uses `Dart Finalizer<_FinalizerToken>` for GC-triggered zeroing as a
  backstop when `dispose` is not called.
- Tracks live instances in debug builds via `ZeroizeConfig.trackAllocate/trackDispose`.

### `SecretIntList`

- Same pattern as `SecretBytes` but for `List<int>`.
- Used for NTT polynomial coefficient arrays in ML-KEM/ML-DSA.
- A `Finalizer` is also attached for GC backstop.

### `SecretBuffer`

- Grows dynamically, zeroing the old allocation before dropping its reference
  on each resize.
- `seal()` atomically transfers content into a new `SecretBytes` and zeros
  the internal buffer.

### `SecretBox<T>`

- Generic opaque wrapper; the caller supplies the zero callback.
- Suitable for any sensitive type that doesn't fit `Uint8List` or `List<int>`.

### `PasswordInput`

- Acknowledges honestly that Dart `String` is immutable and cannot be zeroed.
- Provides `toUtf8SecretBytes()` which produces a zeroable byte representation.
- Documents the byte-collection alternative via `SecretBuffer`.

---

## Layer 5: Lifecycle Management (`src/lifecycle/`)

### `Zeroizable` Mixin

The contract type. Any class holding secrets mixes in `Zeroizable`,
overrides `zeroize()`, and gets `useAndZeroize` / `useAndZeroizeAsync` for free.

### `ZeroizeScope`

RAII scope tracking `Zeroizable` instances. Disposes them in LIFO order
on exit (normal or exceptional). `run` / `runAsync` factory methods
guarantee disposal even when the inner function throws.

### `ZeroizeGuard` Functions

`withZeroizedBytes` / `withZeroizedBytesAsync` — scoped zeroing for raw
`Uint8List` temporaries.

`withZeroized` / `withZeroizedAsync` — scoped zeroing for multiple
`Zeroizable` secrets.

---

## Key Design Decisions

### No `dart:ffi` / `dart:io`

The package targets all Dart platforms including Flutter web and Wasm.
FFI and IO would restrict the target matrix unnecessarily. The known
limitations (GC copying, no `mlock`) are documented explicitly in the
security model.

### `@pragma('vm:never-inline')` over `volatile`

Dart has no `volatile` write primitive. `vm:never-inline` on functions
that read through written pointers achieves an equivalent observable
side-effect from the optimizer's perspective.

### `Finalizer` as Backstop, Not Primary

`dispose()` is the required, deterministic zeroing path. `Finalizer` is
a safety net — GC timing is non-deterministic and the GC may have already
moved the buffer. Production code should always call `dispose()` explicitly,
ideally via `ZeroizeScope` or `useAndZeroize`.

### Debug Tracking via `assert()` Closures

`ZeroizeConfig.trackAllocate/trackDispose` use `assert(() { ... }())`
closures. These are zero-cost in release/AOT builds (the VM removes
assertions entirely). In debug/test builds the counters update, enabling
`debugAssertNoLeaks()` to catch leaks in `tearDown`.

### `SecretBuffer` Old-Allocation Zeroing on Resize

When `SecretBuffer` grows, it copies valid data to the new allocation
and calls `secureZero` on the old `Uint8List` before dropping the
reference. This prevents partial key material from lingering in a GC-
collected old generation buffer without being zeroed.

---

## File Map

```
lib/
├── zeroize.dart                    ← Main barrel export
└── src/
    ├── errors.dart                 ← ZeroizeDisposedError, ZeroizeContractError
    ├── annotations/
    │   └── annotations.dart        ← @sensitive, @constantTime
    ├── config/
    │   └── zeroize_config.dart     ← ZeroizeConfig (pattern, debug tracking)
    ├── core/
    │   ├── dse_guard.dart          ← DSE prevention primitives
    │   ├── overwrite_patterns.dart ← ZeroizePattern enum
    │   └── secure_zero.dart        ← secureZero / secureZeroIntList / secureZeroRange
    ├── ct/
    │   └── ct_ops.dart             ← All constant-time primitives
    ├── containers/
    │   ├── secret_bytes.dart       ← SecretBytes (primary container)
    │   ├── secret_int_list.dart    ← SecretIntList (NTT polynomial container)
    │   ├── secret_buffer.dart      ← SecretBuffer (incremental builder)
    │   ├── secret_box.dart         ← SecretBox<T> (generic wrapper)
    │   └── password_input.dart     ← PasswordInput (string mitigation)
    ├── lifecycle/
    │   ├── zeroizable.dart         ← Zeroizable mixin
    │   ├── zeroize_scope.dart      ← ZeroizeScope (RAII)
    │   └── zeroize_guard.dart      ← withZeroized* guard functions
    ├── extensions/
    │   └── uint8list_extensions.dart ← .secureZeroize() .xorWith() .isAllZero
    └── utils/
        └── pseudo_rng.dart         ← PseudoRng (Xorshift32, non-crypto)
```
