import 'dart:typed_data';

import '../core/overwrite_patterns.dart';
import '../core/secure_zero.dart';
import 'zeroizable.dart';

// ─── Byte-buffer guards ───────────────────────────────────────────────────────

/// Runs [fn] with [data], zeroing [data] unconditionally on exit.
///
/// ```dart
/// final tag = withZeroizedBytes(
///   tempMacKey,
///   (key) => hmacSha3256(key, message),
/// );
/// ```
T withZeroizedBytes<T>(
  Uint8List data,
  T Function(Uint8List data) fn, {
  ZeroizePattern? pattern,
}) {
  try {
    return fn(data);
  } finally {
    secureZero(data, pattern: pattern);
  }
}

/// Async variant of [withZeroizedBytes].
Future<T> withZeroizedBytesAsync<T>(
  Uint8List data,
  Future<T> Function(Uint8List data) fn, {
  ZeroizePattern? pattern,
}) async {
  try {
    return await fn(data);
  } finally {
    secureZero(data, pattern: pattern);
  }
}

// ─── Zeroizable guards ────────────────────────────────────────────────────────

/// Runs [fn] and zeroes all [secrets] in reverse order on exit, even on
/// throw.
///
/// ```dart
/// final ciphertext = withZeroized(
///   [privateKey, ephemeralKey],
///   () => encapsulate(privateKey, ephemeralKey, plaintext),
/// );
/// ```
T withZeroized<T>(List<Zeroizable> secrets, T Function() fn) {
  try {
    return fn();
  } finally {
    for (var i = secrets.length - 1; i >= 0; i--) {
      try {
        secrets[i].zeroize();
      } catch (_) {}
    }
  }
}

/// Async variant of [withZeroized].
Future<T> withZeroizedAsync<T>(
  List<Zeroizable> secrets,
  Future<T> Function() fn,
) async {
  try {
    return await fn();
  } finally {
    for (var i = secrets.length - 1; i >= 0; i--) {
      try {
        secrets[i].zeroize();
      } catch (_) {}
    }
  }
}
