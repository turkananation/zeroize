# Integration Guide

## Integrating with `pqcrypto`

Add to `pubspec.yaml`:

```yaml
dependencies:
  pqcrypto: ^<version>
  zeroize: ^0.1.0
```

### ML-KEM Private Key Lifecycle

```dart
import 'package:zeroize/zeroize.dart';
import 'package:pqcrypto/pqcrypto.dart';

/// Wraps an ML-KEM-768 private key with zeroing semantics.
final class SecureMlKem768PrivateKey with Zeroizable {
  final SecretBytes _dk;          // 2400-byte decapsulation key
  final SecretIntList _s;         // secret vector coefficients
  bool _disposed = false;

  SecureMlKem768PrivateKey._({
    required SecretBytes dk,
    required SecretIntList s,
  })  : _dk = dk,
        _s = s;

  factory SecureMlKem768PrivateKey.fromKeygen(MlKem768Keypair pair) {
    final dk = SecretBytes.fromList(pair.privateKey.bytes);
    SecretIntList? s;
    try {
      s = SecretIntList.fromList(pair.privateKey.sVector);
      return SecureMlKem768PrivateKey._(dk: dk, s: s);
    } catch (e) {
      dk.dispose();
      s?.dispose();
      rethrow;
    }
  }

  /// Decapsulate and return the shared secret as a SecretBytes.
  SecretBytes decapsulate(Uint8List ciphertext) {
    if (_disposed) throw ZeroizeDisposedError('SecureMlKem768PrivateKey');
    return _dk.use((dk) {
      final sharedSecret = MlKem768.decapsulate(dk, _s.use((s) => s), ciphertext);
      return SecretBytes.fromList(sharedSecret);
    });
  }

  @override
  void zeroize() {
    if (_disposed) return;
    _disposed = true;
    _dk.dispose();
    _s.dispose();
  }
}

// Usage in key exchange:
Future<Uint8List> performKem(Uint8List recipientPublicKey) async {
  return ZeroizeScope.runAsync((scope) async {
    final keypair = await MlKem768.generateKeypair();
    final sk = scope.track(SecureMlKem768PrivateKey.fromKeygen(keypair));

    final encapsResult = MlKem768.encapsulate(recipientPublicKey);
    final sharedSecret = scope.track(
      SecretBytes.fromList(encapsResult.sharedSecret),
    );

    // Use sharedSecret for KDF...
    final sessionKey = scope.track(
      SecretBytes.fromList(hkdf(sharedSecret, info: 'session')),
    );

    return sessionKey.use((k) => k.toList());
    // sk, sharedSecret, sessionKey all zeroed on scope exit
  });
}
```

### NTT Polynomial Zeroing

```dart
// During ML-KEM key generation — zero intermediate polynomials
final secretPoly = SecretIntList.ofLength(256); // ML-KEM-768 N=256
final errorPoly  = SecretIntList.ofLength(256);

return ZeroizeScope.run((scope) {
  scope.track(secretPoly);
  scope.track(errorPoly);

  // Fill during keygen
  sampleCBD(secretPoly.mutate((c) => c), eta: 2);
  sampleCBD(errorPoly.mutate((c) => c), eta: 2);

  // NTT
  ntt(secretPoly.mutate((c) => c));
  ntt(errorPoly.mutate((c) => c));

  return computePublicKey(secretPoly, errorPoly);
  // secretPoly and errorPoly zeroed here
});
```

---

## Integrating with `pqforge`

### AEAD Tag Verification

Every authentication tag verification **must** go through `ctVerifyTag`:

```dart
import 'package:zeroize/zeroize.dart';

/// Decrypts and verifies an AEAD-encrypted message.
///
/// Throws [AuthenticationException] if the tag does not match.
Uint8List aeadDecrypt(
  SecretBytes key,
  Uint8List nonce,
  Uint8List ciphertext,
  Uint8List tag,
) {
  return key.use((k) {
    final plaintext = chacha20Decrypt(k, nonce, ciphertext);
    final computedTag = poly1305(k, nonce, ciphertext);

    // CRITICAL: constant-time tag comparison
    if (!ctVerifyTag(computedTag, tag)) {
      // Zero the plaintext before throwing — don't leak it
      plaintext.secureZeroize();
      throw AuthenticationException('AEAD authentication failed');
    }

    return plaintext;
  });
}
```

### Key Derivation Result Handling

```dart
/// Derives session keys from a KEM shared secret.
///
/// The shared secret is zeroed after derivation regardless of success.
Future<SessionKeys> deriveSessionKeys(Uint8List sharedSecret) async {
  final ss = SecretBytes.fromUint8List(sharedSecret);
  sharedSecret.secureZeroize(); // zero transfer copy

  return ss.useAndZeroize(() {
    final hkdfOutput = ss.use((s) => hkdfExpand(s, length: 64));
    final buf = SecretBuffer();
    buf.addBytes(hkdfOutput);
    hkdfOutput.secureZeroize();

    final combined = buf.seal();
    return ZeroizeScope.run((scope) {
      scope.track(combined);
      final sendKey = combined.subrange(0, 32);
      final recvKey = combined.subrange(32, 64);
      return SessionKeys(
        send: sendKey, // caller owns these SecretBytes
        recv: recvKey,
      );
    });
  });
}
```

---

## Integrating with `pqtransport`

### Session Key Lifecycle

```dart
import 'package:zeroize/zeroize.dart';

final class PqTransportSession with Zeroizable {
  final SecretBytes _sendKey;
  final SecretBytes _recvKey;
  final NonceManager _sendNonce;
  final NonceManager _recvNonce;
  bool _disposed = false;

  PqTransportSession._({
    required SecretBytes sendKey,
    required SecretBytes recvKey,
  })  : _sendKey = sendKey,
        _recvKey = recvKey,
        _sendNonce = NonceManager(),
        _recvNonce = NonceManager();

  factory PqTransportSession.fromHandshake(HandshakeResult result) {
    final sendKey = SecretBytes.fromList(result.sendKeyBytes);
    SecretBytes? recvKey;
    try {
      recvKey = SecretBytes.fromList(result.recvKeyBytes);
      return PqTransportSession._(sendKey: sendKey, recvKey: recvKey);
    } catch (e) {
      sendKey.dispose();
      recvKey?.dispose();
      rethrow;
    }
  }

  Uint8List encryptRecord(Uint8List plaintext) {
    if (_disposed) throw ZeroizeDisposedError('PqTransportSession');
    final nonce = _sendNonce.nextNonce();
    return _sendKey.use((k) => aeadEncrypt(k, nonce, plaintext));
  }

  Uint8List decryptRecord(Uint8List ciphertext, Uint8List tag, Uint8List nonce) {
    if (_disposed) throw ZeroizeDisposedError('PqTransportSession');
    return _recvKey.use((k) {
      final computed = aeadComputeTag(k, nonce, ciphertext);
      if (!ctVerifyTag(computed, tag)) {
        computed.secureZeroize();
        throw AuthenticationException('Record authentication failed');
      }
      computed.secureZeroize();
      return aeadDecryptVerified(k, nonce, ciphertext);
    });
  }

  /// Zero all session keys — call on normal close AND on any error.
  @override
  void zeroize() {
    if (_disposed) return;
    _disposed = true;
    _sendKey.dispose();
    _recvKey.dispose();
  }
}
```

### Handshake Secrets

```dart
/// Performs a PQ hybrid handshake and derives session keys.
///
/// All intermediate secrets are zeroed regardless of outcome.
Future<PqTransportSession> handshake(
  Socket socket,
  Uint8List peerPublicKey,
) async {
  return ZeroizeScope.runAsync((scope) async {
    // KEM encapsulation
    final kemResult = MlKem768.encapsulate(peerPublicKey);
    final kemSS = scope.track(SecretBytes.fromList(kemResult.sharedSecret));

    // X25519 ECDH (hybrid)
    final dhSS = scope.track(await ecdhX25519(socket));

    // Key derivation
    final combined = scope.track(kemSS.concat(dhSS));
    final master = scope.track(
      SecretBytes.fromList(hkdfExtract(combined)),
    );

    // Derive send/recv keys
    final derived = deriveTrafficKeys(master);

    // Send KEM ciphertext
    await socket.send(kemResult.ciphertext);

    return PqTransportSession.fromHandshake(HandshakeResult(
      sendKeyBytes: derived.send,
      recvKeyBytes: derived.recv,
    ));
    // kemSS, dhSS, combined, master all zeroed on scope exit
  });
}
```

---

## Common Pattern: Transfer Copy Zeroing

Any time key material crosses a boundary (isolate, function, buffer),
zero the transfer copy immediately:

```dart
// After Isolate.run
final rawKey = await Isolate.run(generateRawKey);
final key = SecretBytes.fromList(rawKey);
rawKey.secureZeroize(); // ← always

// After fromList
final src = computeKey();
final secret = SecretBytes.fromList(src);
src.secureZeroize(); // ← always, if src is also sensitive

// After KDF output
final kdfOut = hkdfExpand(prk, length: 64);
final sessionKey = SecretBytes.fromUint8List(kdfOut);
kdfOut.secureZeroize(); // ← always
```

---

## `pubspec.yaml` Snippet

```yaml
dependencies:
  zeroize: ^0.1.0
  pqcrypto: ^<version>   # ML-KEM, ML-DSA
  pqforge: ^<version>    # Application-layer PQC operations
  pqtransport: ^<version> # PQ-secure transport
```
