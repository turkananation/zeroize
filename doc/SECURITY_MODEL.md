# Security Model

## Threat Model

`zeroize` is designed to minimise the window during which secret key
material exists in process memory.  The primary adversaries considered:

1. **Memory scraping after process crash** — core dumps or crash reporters
   that capture heap contents.
2. **Cold-boot / DRAM remanence** — physical memory inspection after power
   loss (mitigated by multi-pass overwrite patterns).
3. **Timing side-channels** — timing oracles in comparison and tag
   verification operations.
4. **Compiler optimisation** — Dead Store Elimination removing zeroing
   writes before they occur.

---

## What This Library Protects Against

### Dead Store Elimination (DSE)

**Threat:** The Dart AOT compiler proves a write is never read and removes
it.  This is the most dangerous compiler optimisation for zeroing code.

**Mitigation:** The `_dseOpaqueSink` pattern.  A package-level mutable
variable is XOR'd with the buffer content via a `@pragma('vm:never-inline')`
function *after* each overwrite pass.  The compiler must preserve all writes
because an opaque (non-inlineable) function observably reads through the
pointer after them.

**Confidence:** High in AOT release builds.  The `vm:never-inline` pragma
is a hard compiler directive, not a hint.

### Timing Side-Channels in Comparisons

**Threat:** Using `==` or `ListEquality` on authentication tags creates a
timing oracle that leaks the position of the first differing byte, enabling
forgery attacks.

**Mitigation:** All comparison operations (`ctEquals`, `ctVerifyTag`,
`timingSafeEquals`) use XOR accumulators that scan the full buffer length
regardless of content.  Integer predicates use two's-complement bit
manipulation without branches.

**Confidence:** High in AOT release builds on Dart VM x64/arm64.

### Accidental Secret Retention (GC backstop)

**Threat:** Code that creates a `SecretBytes` but forgets to call
`dispose()`.

**Mitigation:** `Dart Finalizer` is attached at construction time.  If the
`SecretBytes` object is garbage collected without `dispose()`, the finalizer
zeroes the current live backing buffer.

**Confidence:** Medium.  The finalizer only zeroes the *current live copy*;
if the GC has moved the buffer, the old copy at the previous address may
not be zeroed.  Explicit `dispose()` is always preferred.

---

## Known Limitations (Acknowledged)

### GC Copying

**Root cause:** Dart uses a semi-space scavenging GC.  When a `Uint8List`
survives a minor collection, it may be copied to a new heap address.  The
old copy at the original address is never explicitly zeroed by this library
— only the current live copy referenced by `_data` is zeroed on `dispose()`.

**Impact:** A window exists where secret bytes may linger at an old heap
address until the memory is reused.  This is a fundamental limitation of
pure Dart and cannot be solved without `dart:ffi`.

**Workaround:** Run cryptographic key derivation and short-lived key
material in a dedicated `Isolate`.  When the isolate exits, its entire heap
is reclaimed by the OS, providing bulk cleanup regardless of GC copying.

```dart
// Key generation in a short-lived isolate — heap discarded on exit.
import 'dart:isolate';
final rawKey = await Isolate.run(generateRawKey);
final sessionKey = SecretBytes.fromList(rawKey);
rawKey.secureZeroize(); // zero the transfer copy
```

### JIT Timing Violations

**Root cause:** Debug and profile builds use the Dart JIT compiler, which
speculatively recompiles hot paths based on runtime profiling data.  This
can eliminate branches and reorder operations, breaking constant-time
source-level assumptions.

**Impact:** The `ct*` functions are NOT constant-time in JIT builds.

**Requirement:** Always deploy cryptographic code as AOT-compiled release
binaries.

```sh
dart compile exe          # server / CLI
flutter build --release   # mobile / desktop
```

### JavaScript / Wasm

**Root cause:** Dart-to-JS and Dart-to-Wasm compilers produce code that runs
in a managed JS or Wasm runtime.  These runtimes have their own optimisers
and garbage collectors with no CT guarantees.

**Impact:** The `ct*` functions do NOT provide constant-time guarantees when
compiled to JavaScript or Wasm.

**Recommendation:** Do not use `ct*` functions for cryptographic security on
web targets.  Use WebCrypto (via JS interop) for browser-side cryptography.

### OS Memory Remanence

**Root cause:** Without `dart:ffi` there is no access to `mlock()`
(Linux/macOS) or `VirtualLock()` (Windows) to prevent the OS from swapping
secret memory pages to disk.

**Impact:** On systems with swap enabled, secret key material may be written
to disk in a swap page.

**Mitigation:** Disable swap, or use the OS-level encrypted swap (FileVault,
dm-crypt) as a system-level mitigation.

---

## Deployment Checklist

```
✓ Compile as AOT release binary (dart compile exe / flutter build --release)
✓ Always call dispose() explicitly on SecretBytes/SecretIntList/SecretBuffer
✓ Use ZeroizeScope to guarantee disposal even on exceptions
✓ Use ctVerifyTag() for ALL AEAD/MAC tag comparisons — never ==
✓ Use timingSafeEquals() for key equality checks
✓ Run key generation in short-lived Isolates where possible
✓ Zero the raw transfer copy immediately after wrapping in SecretBytes
✓ Never log secret values; log opaque handles (hashCode) instead
✓ Set ZeroizePattern.dod or .gutmann7 for high-assurance deployments
```

---

## Cryptographic Attestation Statement

This library does **not** make formal claims of FIPS 140-3 compliance,
Common Criteria certification, or any other government cryptographic
standard certification.  It provides best-effort mitigations in pure Dart.

For evaluated, certified implementations see the NIST Cryptographic Module
Validation Program (CMVP) for hardware security modules or validated
software modules.

---

## Responsible Disclosure

Security vulnerabilities should be reported via email to
`security@turkananation.dev`.  See [SECURITY.md](../SECURITY.md) for the
full policy.
