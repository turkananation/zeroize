# API Guide

## Import

```dart
import 'package:zeroize/zeroize.dart';
```

---

## Zeroing Raw Buffers

Use when you already have a `Uint8List` or `List<int>` that you need to
zero in-place after use.

```dart
// Uint8List — default twoPass pattern
secureZero(myUint8List);

// Explicit pattern
secureZero(myUint8List, pattern: ZeroizePattern.dod);

// Sub-region only (offset=16, count=32)
secureZeroRange(buffer, 16, 32);

// NTT polynomial coefficient arrays
secureZeroIntList(nttCoeffs);
secureZeroIntList(nttCoeffs, pattern: ZeroizePattern.gutmann7);

// Extension method shorthand
myUint8List.secureZeroize();
myList.secureZeroize(pattern: ZeroizePattern.pseudoRandom);
```

---

## `SecretBytes` — Primary Container

**Always** wrap secret key material in `SecretBytes` immediately.

```dart
// From a List<int> (copies source)
final key = SecretBytes.fromList(rawKeyBytes);

// From an existing Uint8List (copies source — caller keeps ownership)
final key = SecretBytes.fromUint8List(rawUint8List);

// Pre-allocated zero buffer
final slot = SecretBytes.ofLength(32);

// Generated inline (avoids intermediate plain List)
final key = SecretBytes.generate(32, (i) => keySchedule[i]);
```

### Access Model

```dart
// ✅ Read-only access — reference does not escape
final digest = key.use((bytes) => sha3_256(bytes, message));

// ✅ Read/write in-place — reference does not escape
key.mutate((bytes) => fillFromKdf(bytes));

// ❌ WRONG — retaining the reference defeats disposal
Uint8List dangerousRef;
key.use((bytes) => dangerousRef = bytes); // never do this
```

### Disposal

```dart
// Explicit — preferred
key.dispose();

// Via ZeroizeScope (automatic, even on exception)
final result = ZeroizeScope.run((scope) {
  final k = scope.track(SecretBytes.fromList(raw));
  return encrypt(k, plaintext);
}); // k is zeroed here

// Via useAndZeroize
final ct = key.useAndZeroize(() => encrypt(key, plaintext));
// key is zeroed after encrypt() returns

// Via withZeroizedBytes (for raw Uint8List temporaries)
final tag = withZeroizedBytes(
  tempMacKey,
  (k) => hmac(k, message),
);
```

### Operations

```dart
// XOR in-place with mask
key.xorWith(Uint8List.fromList(otherKey));

// Fill all bytes with a value
key.fill(0xCC);

// Subrange (independent copy)
final subkey = key.subrange(0, 16); // bytes [0..15]
// ... use subkey ...
subkey.dispose();

// Concatenate
final combined = key1.concat(key2);
combined.dispose();
```

### Constant-Time Comparison

```dart
// Against another SecretBytes
if (!key1.timingSafeEquals(key2)) {
  throw SecurityException('Key mismatch');
}

// Against a plain Uint8List
if (!key.timingSafeEqualsBytes(expectedBytes)) {
  throw SecurityException('Tag mismatch');
}
```

---

## `SecretIntList` — For Polynomial Arrays

```dart
// Allocate 256-element polynomial (ML-KEM)
final poly = SecretIntList.ofLength(256);

// Fill during NTT
for (var i = 0; i < 256; i++) poly[i] = nttResult[i];

// In-place access
poly.mutate((coeffs) { /* modify coeffs */ });

// Read access
final sum = poly.use((c) => c.fold<int>(0, (a, v) => a + v));

poly.dispose();
```

---

## `SecretBuffer` — Incremental Building

```dart
final buf = SecretBuffer();

// Add from multiple sources
buf.addByte(0xAB);
buf.addBytes(Uint8List.fromList([0x01, 0x02]));
buf.addList([0x03, 0x04]);
buf.addFill(0x00, 16); // 16 zero-padding bytes

// Seal: transfer to SecretBytes and dispose buffer
final secret = buf.seal();
try {
  doWork(secret);
} finally {
  secret.dispose();
}
```

---

## `SecretBox<T>` — Generic Wrapper

```dart
// Wrap any type with a custom zero callback
final box = SecretBox<MyPrivateKey>(
  MyPrivateKey.generate(),
  (key) {
    key.rawBytes.secureZeroize();
    key.clearSchedule();
  },
);

final sig = box.use((key) => sign(message, key));
box.dispose(); // zeroCallback invoked once
```

---

## `PasswordInput`

```dart
// Collect from UI layer
final pwd = PasswordInput(textFieldController.text);

// The Dart String cannot be zeroed — only the UTF-8 encoding can
final pwdBytes = pwd.toUtf8SecretBytes();
try {
  final derived = argon2id(pwdBytes, salt, ...);
  // use derived key
} finally {
  pwdBytes.dispose();
  pwd.dispose();
}
```

**Maximum assurance alternative — collect byte by byte:**

```dart
final buf = SecretBuffer();
for (final byte in keyboardScanCodes) buf.addByte(byte);
final pwdBytes = buf.seal();
// No Dart String is ever created
```

---

## Constant-Time Operations

```dart
// Tag verification — ALWAYS use this for AEAD/MAC
if (!ctVerifyTag(expectedTag, receivedTag)) {
  throw AuthenticationException('Authentication failed');
}

// Key equality
if (!ctEquals(derivedKey, storedKey)) {
  throw SecurityException('Key mismatch');
}

// Modular arithmetic for NTT (ML-KEM q=3329)
final reduced = ctReduceOnce(v, 3329);
final positive = ctLiftToPositive(v, 3329);

// Branchless integer select
final selected = ctSelect(condition, valueIfTrue, valueIfFalse);

// CT conditional copy/swap (for ladder algorithms)
ctConditionalCopy(bit, dst, src);
ctConditionalSwap(bit, a, b);
```

---

## `ZeroizeScope`

```dart
// Synchronous
final result = ZeroizeScope.run((scope) {
  final a = scope.track(SecretBytes.fromList(rawA));
  final b = scope.track(SecretBytes.fromList(rawB));
  return combine(a, b);
}); // a and b zeroed in LIFO order (b first, then a)

// Asynchronous
final ciphertext = await ZeroizeScope.runAsync((scope) async {
  final sessionKey = scope.track(await deriveSessionKey());
  return await aeadEncrypt(sessionKey, plaintext);
});
```

---

## `Zeroizable` Mixin for Your Types

```dart
final class MlKemPrivateKey with Zeroizable {
  final SecretBytes _seed;     // 32-byte seed (d || z)
  final SecretIntList _s;      // secret vector s
  bool _disposed = false;

  MlKemPrivateKey._(this._seed, this._s);

  // Factory that zeroes on error mid-construction
  factory MlKemPrivateKey.generate(KeygenInput input) {
    final seed = SecretBytes.fromList(input.seed);
    SecretIntList? s;
    try {
      s = SecretIntList.fromList(computeS(input));
      return MlKemPrivateKey._(seed, s);
    } catch (e) {
      seed.dispose();
      s?.dispose();
      rethrow;
    }
  }

  Uint8List decapsulate(Uint8List ct) =>
      useAndZeroize(() => _mlkemDecaps(_seed, _s, ct));

  @override
  void zeroize() {
    if (_disposed) return;
    _disposed = true;
    _seed.dispose();
    _s.dispose();
  }
}
```

---

## Configuration

```dart
// Set at startup — before any zeroize operations
void main() {
  // Use 3-pass DoD pattern for all operations by default
  ZeroizeConfig.setDefaultPattern(ZeroizePattern.dod);
  runApp();
}

// Debug: verify all secrets disposed in test tearDown
tearDown(() => ZeroizeConfig.debugAssertNoLeaks());
```

---

## Common Anti-Patterns

```dart
// ❌ Don't: use == for tag comparison
if (computedTag == receivedTag) { ... }      // timing oracle

// ✅ Do:
if (!ctVerifyTag(computedTag, receivedTag)) throw AuthenticationException();

// ❌ Don't: keep a SecretBytes reference after dispose
key.dispose();
final len = key.length;   // throws ZeroizeDisposedError

// ❌ Don't: log secret material
log('Derived key: ${key.use((b) => b.toHexString())}'); // never!

// ✅ Do: log opaque handles
log('Key handle: ${key.hashCode.toRadixString(16)}');

// ❌ Don't: throw with key material in the message
throw Exception('Failed with key $rawKey');

// ✅ Do:
throw CryptoException('Key derivation failed', code: ErrorCode.kdfError);

// ❌ Don't: forget dispose in error paths
SecretBytes? key;
try {
  key = SecretBytes.fromList(raw);
  return encrypt(key, pt); // if this throws, key leaks
} catch (e) { rethrow; }

// ✅ Do: use ZeroizeScope
return ZeroizeScope.run((scope) {
  final key = scope.track(SecretBytes.fromList(raw));
  return encrypt(key, pt); // scope zeroes key on any exit
});
```
