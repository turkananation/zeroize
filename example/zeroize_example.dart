// ignore_for_file: avoid_print
import 'dart:typed_data';

import 'package:zeroize/zeroize.dart';

// ─── Simulated crypto primitives (stand-ins for real implementations) ─────────

Uint8List simulateEncrypt(SecretBytes key, Uint8List plaintext) {
  // Real implementation would use AES-GCM, ChaCha20-Poly1305, etc.
  return key.use((k) {
    final ct = Uint8List(plaintext.length);
    for (var i = 0; i < plaintext.length; i++) {
      ct[i] = plaintext[i] ^ k[i % k.length];
    }
    return ct;
  });
}

Uint8List simulateKdf(Uint8List ikm) {
  // Real implementation would use HKDF, Argon2, PBKDF2, etc.
  final out = Uint8List(32);
  for (var i = 0; i < 32; i++) {
    out[i] = (ikm[i % ikm.length] ^ 0x5A) & 0xFF;
  }
  return out;
}

// ─── Example 1: Basic SecretBytes lifetime ────────────────────────────────────

void example1BasicLifetime() {
  print('\n=== Example 1: Basic SecretBytes lifetime ===');

  // Raw key material arrives from key exchange or KDF.
  final rawKey = Uint8List.fromList(List<int>.generate(32, (i) => i));

  // Immediately wrap in SecretBytes.
  final key = SecretBytes.fromUint8List(rawKey);

  // Zero the transfer copy we no longer need.
  rawKey.secureZeroize();

  try {
    final plaintext = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]);
    final ciphertext = simulateEncrypt(key, plaintext);
    print('Ciphertext: ${ciphertext.toHexString()}');
  } finally {
    key.dispose(); // deterministic, multi-pass zeroing
    print('Key disposed: ${key.isDisposed}');
  }
}

// ─── Example 2: ZeroizeScope for multiple secrets ─────────────────────────────

void example2ZeroizeScope() {
  print('\n=== Example 2: ZeroizeScope for multiple secrets ===');

  final rawIkm = Uint8List.fromList(List<int>.generate(32, (i) => i * 2));

  final result = ZeroizeScope.run((scope) {
    // Derive a session key from IKM — both live in the scope.
    final ikmSecret = scope.track(SecretBytes.fromUint8List(rawIkm));
    final derivedKey = scope.track(
      SecretBytes.fromList(
        ikmSecret.use((ikm) => simulateKdf(ikm)),
      ),
    );

    // Use derived key for encryption.
    final plaintext = Uint8List.fromList('hello pqcrypto'.codeUnits);
    return simulateEncrypt(derivedKey, plaintext);
    // Both ikmSecret and derivedKey are zeroed here, even if encryption threw.
  });

  rawIkm.secureZeroize();
  print('Encrypted result: ${result.toHexString()}');
}

// ─── Example 3: SecretBuffer for incremental key building ────────────────────

void example3SecretBuffer() {
  print('\n=== Example 3: SecretBuffer for incremental key building ===');

  final buf = SecretBuffer();

  // Simulate concatenating KDF outputs block by block.
  final block1 = Uint8List.fromList(List<int>.generate(16, (i) => i));
  final block2 = Uint8List.fromList(List<int>.generate(16, (i) => i + 16));

  buf.addBytes(block1);
  buf.addBytes(block2);
  print('Accumulated ${buf.length} bytes');

  // Seal transfers ownership to SecretBytes; buf is disposed.
  final sessionKey = buf.seal();
  print('Buffer sealed. isDisposed=${buf.isDisposed}');

  sessionKey.use((k) => print('Session key length: ${k.length}'));
  sessionKey.dispose();
}

// ─── Example 4: PasswordInput for KDF feeding ────────────────────────────────

void example4PasswordInput() {
  print('\n=== Example 4: PasswordInput ===');

  // In a real app, collect from UI — never from a plain String if avoidable.
  final pwd = PasswordInput('correct-horse-battery-staple');

  // toUtf8SecretBytes() CAN be zeroed; the source String cannot.
  final pwdBytes = pwd.toUtf8SecretBytes();
  print('Password byte length: ${pwdBytes.length}');

  // Feed pwdBytes into a KDF here (PBKDF2, Argon2, scrypt, etc.)
  pwdBytes.dispose();
  pwd.dispose();
  print('Password bytes disposed: ${pwdBytes.isDisposed}');
}

// ─── Example 5: Constant-time tag verification ────────────────────────────────

void example5CtTagVerification() {
  print('\n=== Example 5: Constant-time tag verification ===');

  final expectedTag = Uint8List.fromList(List<int>.generate(32, (i) => i));
  final receivedTag = Uint8List.fromList(List<int>.generate(32, (i) => i));
  final tamperedTag = Uint8List.fromList(List<int>.generate(32, (i) => i));
  tamperedTag[15] ^= 0x01;

  // NEVER use == or ListEquality for AEAD/MAC tags — timing oracle!
  print('Valid tag:   ${ctVerifyTag(expectedTag, receivedTag)}');
  print('Tampered:    ${ctVerifyTag(expectedTag, tamperedTag)}');

  // Timing-safe equality on SecretBytes
  final keyA = SecretBytes.fromList(List<int>.generate(32, (i) => i));
  final keyB = SecretBytes.fromList(List<int>.generate(32, (i) => i));
  print('Keys equal:  ${keyA.timingSafeEquals(keyB)}');
  keyA.dispose();
  keyB.dispose();
}

// ─── Example 6: ZeroizePattern selection ─────────────────────────────────────

void example6ZeroizePatterns() {
  print('\n=== Example 6: ZeroizePattern selection ===');

  // Set the global default.
  ZeroizeConfig.setDefaultPattern(ZeroizePattern.dod);

  final secret = SecretBytes.fromList(List<int>.filled(32, 0xFF));
  secret.dispose(); // Uses ZeroizePattern.dod (3 passes).

  // Or specify per-operation.
  final tmp = Uint8List.fromList(List<int>.filled(64, 0xAB));
  secureZero(tmp, pattern: ZeroizePattern.gutmann7); // 7 passes.
  print('gutmann7 zeroed: ${tmp.isAllZero}');

  // Reset to default for the rest of the program.
  ZeroizeConfig.setDefaultPattern(ZeroizePattern.twoPass);
}

// ─── Example 7: withZeroized guard ───────────────────────────────────────────

void example7Guards() {
  print('\n=== Example 7: withZeroized guards ===');

  final tempKey = Uint8List.fromList(List<int>.generate(32, (i) => i));

  // withZeroizedBytes zeroes tempKey even if the lambda throws.
  final result = withZeroizedBytes(
    tempKey,
    (key) => simulateKdf(key),
  );

  print('Derived: ${result.toHexString().substring(0, 16)}...');
  print('tempKey zeroed: ${tempKey.isAllZero}');
}

// ─── Example 8: Custom type with SecretBox ────────────────────────────────────

class EphemeralKeypair {
  final Uint8List publicKey;
  final Uint8List secretKey;

  EphemeralKeypair(this.publicKey, this.secretKey);

  void zeroize() {
    secretKey.secureZeroize();
    // publicKey does not need zeroing — it's public.
  }
}

void example8SecretBox() {
  print('\n=== Example 8: SecretBox with custom type ===');

  final box = SecretBox<EphemeralKeypair>(
    EphemeralKeypair(
      Uint8List.fromList(List<int>.filled(32, 0x01)),
      Uint8List.fromList(List<int>.filled(32, 0x02)),
    ),
    (kp) => kp.zeroize(),
  );

  box.use(
      (kp) => print('PK: ${kp.publicKey.toHexString().substring(0, 8)}...'));
  box.dispose();
  print('Keypair disposed: ${box.isDisposed}');
}

// ─── Main ─────────────────────────────────────────────────────────────────────

void main() {
  example1BasicLifetime();
  example2ZeroizeScope();
  example3SecretBuffer();
  example4PasswordInput();
  example5CtTagVerification();
  example6ZeroizePatterns();
  example7Guards();
  example8SecretBox();

  print('\nAll examples completed.');
}
