# zeroize

[![pub package](https://img.shields.io/pub/v/zeroize.svg)](https://pub.dev/packages/zeroize)
[![Dart SDK](https://img.shields.io/badge/SDK-%3E%3D3.3.0-blue)](https://dart.dev)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

**Best-effort secret memory zeroing, constant-time operations, and secure
containers for pure Dart.**

No FFI. No `dart:io`. Runs on Android, iOS, macOS, Windows, Linux and web
(CT caveats apply on JIT/JS/Wasm — see [Security Model](#security-model)).

Designed for post-quantum cryptography libraries (`pqcrypto`, `pqforge`,
`pqtransport`) and any Dart project that handles secret key material,
passwords, or authentication tags.

---

## Features

| Feature | API |
| --------- | ----- |
| Multi-pass secure zeroing | `secureZero`, `secureZeroIntList`, `secureZeroRange` |
| 6 overwrite patterns | `ZeroizePattern` (zero · ones · twoPass · dod · pseudoRandom · gutmann7) |
| DSE-resistant zeroing | `@pragma('vm:never-inline')` guard pattern |
| Finalizer-backed container | `SecretBytes` |
| Integer-list container | `SecretIntList` |
| Incremental accumulator | `SecretBuffer` |
| Generic secret wrapper | `SecretBox<T>` |
| Password input handler | `PasswordInput` |
| RAII scope management | `ZeroizeScope` · `withZeroized*` · `withZeroizedBytes*` |
| CT byte comparison | `ctEquals` · `ctVerifyTag` |
| CT integer ops | `ctSelect` · `ctIntEquals` · `ctLessThan` · `ctAbs` … |
| CT buffer ops | `ctConditionalCopy` · `ctConditionalSwap` |
| CT modular arithmetic | `ctReduceOnce` · `ctLiftToPositive` (ML-KEM / ML-DSA) |
| Extension methods | `.secureZeroize()` · `.xorWith()` · `.isAllZero` · `.toHexString()` |
| Debug leak tracking | `ZeroizeConfig.debugAssertNoLeaks()` |
| Static annotations | `@sensitive` · `@constantTime` |

---

## Security Model

`zeroize` provides **best-effort** mitigations.  Read this section before
shipping cryptographic code.

### What it protects against

**Dead Store Elimination (DSE):** The Dart AOT compiler can prove a write
is never read and eliminate it.  `zeroize` defeats this via
`@pragma('vm:never-inline')` boundary functions that observably read
through the pointer after every overwrite pass.

**Timing side-channels:** All comparison and tag-verification operations
use branchless, data-independent algorithms that run in time proportional
to buffer length, not buffer content.

**Accidental retention:** `SecretBytes` attaches a `Dart Finalizer` that
zeroes the backing buffer if the object is GC'd without `dispose()`.

### What it does NOT protect against

**GC copying:** Dart's semi-space GC may copy a `Uint8List` to a new heap
address before zeroing.  The old copy is not zeroed.  (Workaround: run
cryptographic operations in a short-lived `Isolate`.)

**JIT timing violations:** Debug/profile builds use the JIT, which can
break constant-time source-level guarantees.  Use AOT release builds.

**JavaScript/Wasm:** JS engines and the Wasm compiler offer no CT
guarantees.  Do not use `ct*` functions for cryptographic security on web.

**OS remanence:** No `mlock`/`VirtualLock` equivalent without `dart:ffi`.

### Deployment requirement

```sh
dart compile exe          # server / CLI
flutter build --release   # mobile / desktop
```

**Never deploy cryptographic code built with `flutter run` or `dart run`.**

---

## Getting Started

```yaml
# pubspec.yaml
dependencies:
  zeroize: ^0.1.0
```

```dart
import 'package:zeroize/zeroize.dart';
```

---

## Usage

### Wrap key material immediately

```dart
final rawKey = getKeyFromKdf();                          // some List<int>
final key = SecretBytes.fromList(rawKey);
rawKey.secureZeroize();                                  // zero the source copy

try {
  final ciphertext = aeadEncrypt(key, nonce, plaintext);
  return ciphertext;
} finally {
  key.dispose();                                         // multi-pass zeroing
}
```

### `ZeroizeScope` — automatic cleanup

```dart
final ciphertext = await ZeroizeScope.runAsync((scope) async {
  final dk = scope.track(await kdf.derive(inputKey));
  final ek = scope.track(await kem.encapsulate(peerPk));
  return await handshake(dk, ek);
  // dk and ek are zeroed here — even if handshake() threw
});
```

### Access model — never expose the raw buffer

```dart
// ✅ Correct — reference stays inside the callback
final digest = key.use((bytes) => sha3_256(bytes, message));

// ✅ Correct — in-place mutation
key.mutate((bytes) => fillFromKdf(bytes));

// ❌ Wrong — retained reference defeats disposal
Uint8List leaked;
key.use((bytes) => leaked = bytes);   // never do this
```

### `SecretBuffer` — incremental building

```dart
final buf = SecretBuffer();
for (final block in kdfOutputStream) buf.addBytes(block);

final sessionKey = buf.seal();        // buf disposed; caller owns sessionKey
try {
  useKey(sessionKey);
} finally {
  sessionKey.dispose();
}
```

### CT tag verification — never use `==`

```dart
// ❌ Wrong — timing oracle
if (computedTag == receivedTag) { ... }

// ✅ Correct — constant-time
if (!ctVerifyTag(computedTag, receivedTag)) {
  throw AuthenticationException('AEAD authentication failed');
}
```

### CT modular arithmetic for NTT (ML-KEM / ML-DSA)

```dart
// Branchless Barrett-style reduction into [0, q)
final v = ctReduceOnce(rawValue, 3329);        // ML-KEM q = 3329

// Lift negative value into [0, q)
final u = ctLiftToPositive(signedValue, 8380417); // ML-DSA q = 8380417

// Branchless select, conditional copy/swap
final chosen  = ctSelect(condition, ifOne, ifZero);
ctConditionalCopy(bit, dst, src);
ctConditionalSwap(bit, a, b);
```

### `Zeroizable` mixin for your key types

```dart
final class MlKemPrivateKey with Zeroizable {
  final SecretBytes _seed;
  final SecretIntList _s;      // private polynomial vector
  bool _disposed = false;

  @override
  void zeroize() {
    if (_disposed) return;
    _disposed = true;
    _seed.dispose();
    _s.dispose();
  }

  // useAndZeroize runs fn then always calls zeroize()
  Uint8List decapsulate(Uint8List ct) =>
      useAndZeroize(() => _decaps(_seed, _s, ct));
}
```

### `ZeroizePattern` selection

```dart
// Set global default at startup
ZeroizeConfig.setDefaultPattern(ZeroizePattern.dod);

// Or per-call
secureZero(buffer, pattern: ZeroizePattern.gutmann7);
final key = SecretBytes.fromList(raw, pattern: ZeroizePattern.dod);
```

### Debug leak detection in tests

```dart
import 'package:test/test.dart';
import 'package:zeroize/zeroize.dart';

void main() {
  tearDown(() => ZeroizeConfig.debugAssertNoLeaks());

  test('key is disposed after use', () {
    final key = SecretBytes.fromList([1, 2, 3, 4]);
    key.use((b) => expect(b[0], equals(1)));
    key.dispose();
    // tearDown will fail if any SecretBytes leaks
  });
}
```

---

## Choosing a Pattern

| Pattern | Passes | Use Case |
| --------- | -------- | ---------- |
| `zero` | 1 | Fastest; NIST SP 800-88 Rev 1 for DRAM |
| `ones` | 1 | Complement baseline |
| `twoPass` | 2 | **Default** — strong DSE resistance |
| `dod` | 3 | High-assurance production |
| `pseudoRandom` | 2 | Bit-pattern diversity + final zero |
| `gutmann7` | 7 | Maximum best-effort in pure Dart |

> **Note:** On modern DRAM, multiple passes add DSE resistance and
> bit-pattern diversity — not demagnetisation protection (which only
> applies to magnetic media).

---

## Integration with pqcrypto / pqforge / pqtransport

See [doc/INTEGRATION.md](doc/INTEGRATION.md) for complete integration
patterns including ML-KEM private key lifecycle, AEAD tag verification,
handshake secret management, and NTT polynomial zeroing.

---

## Platform Support

| Target | Zeroing | Constant-Time |
| -------- | --------- | --------------- |
| Dart VM — AOT release | ✅ Best-effort | ✅ Source-level CT |
| Flutter Android/iOS — release | ✅ Best-effort | ✅ Source-level CT |
| Flutter macOS/Windows/Linux — release | ✅ Best-effort | ✅ Source-level CT |
| Dart VM — JIT debug/profile | ✅ Best-effort | ⚠️ No CT guarantee |
| Dart-to-JavaScript | ✅ Best-effort | ❌ No CT guarantee |
| Dart-to-Wasm | ✅ Best-effort | ❌ No CT guarantee |

---

## Further Reading

- [doc/ARCHITECTURE.md](doc/ARCHITECTURE.md) — Layer-by-layer design rationale
- [doc/SECURITY_MODEL.md](doc/SECURITY_MODEL.md) — Full threat model and mitigations
- [doc/API_GUIDE.md](doc/API_GUIDE.md) — Detailed API usage with examples
- [doc/FEATURES.md](doc/FEATURES.md) — Complete feature catalogue
- [doc/ROADMAP.md](doc/ROADMAP.md) — Future plans
- [SECURITY.md](SECURITY.md) — Vulnerability reporting

---

## License

MIT — see [LICENSE](LICENSE).

---

## Author

eSiasa — [github.com/turkananation](https://github.com/turkananation)
