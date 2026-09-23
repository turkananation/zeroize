import 'dart:convert';
import 'dart:typed_data';

import '../core/overwrite_patterns.dart';
import '../errors.dart';
import 'secret_bytes.dart';

/// A wrapper for password or passphrase input that minimises heap exposure.
///
/// ## Critical Limitation: Dart String Immutability
///
/// Dart [String] objects are **immutable and may be interned** by the VM.
/// This means:
///
/// - The UTF-16 backing cannot be overwritten — ever.
/// - The GC controls reclamation; there is no `SecureString` equivalent.
/// - [dispose] only nulls the reference — it cannot zero the string data.
///
/// [PasswordInput] mitigates this by:
/// 1. Acknowledging the unavoidable [String] limitation honestly.
/// 2. Providing [toUtf8SecretBytes] — the UTF-8 byte representation *can*
///    be zeroed and is the form used for KDF/PBKDF2/Argon2 inputs.
/// 3. Discarding the reference as soon as [dispose] is called.
///
/// ### Maximum-Assurance Alternative
///
/// For the highest assurance, collect passwords byte-by-byte (e.g. from
/// keyboard scan codes) into a [SecretBuffer] and seal it — a [String] is
/// never created:
///
/// ```dart
/// final buf = SecretBuffer();
/// for (final byte in bytesFromKeyboard) buf.addByte(byte);
/// final password = buf.seal();
/// ```
final class PasswordInput {
  String? _password;
  bool _disposed = false;

  /// Creates a [PasswordInput] wrapping [password].
  PasswordInput(String password) : _password = password;

  /// Whether [dispose] has been called.
  bool get isDisposed => _disposed;

  /// UTF-16 code-unit length.
  ///
  /// For BMP characters this equals the character count.  For supplementary
  /// characters (emoji, etc.) each character is two code units.
  int get codeUnitLength {
    _assertLive();
    return _password!.length;
  }

  // ─── Encoding ─────────────────────────────────────────────────────────────

  /// Encodes the password as UTF-8 and wraps it in a [SecretBytes].
  ///
  /// The returned [SecretBytes] **can** be zeroed — call
  /// [SecretBytes.dispose] when KDF operations complete.  The source
  /// [String] persists on the Dart heap regardless.
  ///
  /// The caller takes ownership of the returned [SecretBytes].
  SecretBytes toUtf8SecretBytes({ZeroizePattern? pattern}) {
    _assertLive();
    return SecretBytes.fromList(
      utf8.encode(_password!),
      pattern: pattern,
    );
  }

  /// Encodes each Unicode code point as a big-endian 32-bit integer.
  ///
  /// Produces 4 × (rune count) bytes.  Useful when the downstream KDF
  /// requires a full code-point representation rather than UTF-8.
  SecretBytes toCodePointsBytes({ZeroizePattern? pattern}) {
    _assertLive();
    final runes = _password!.runes.toList(growable: false);
    final bytes = Uint8List(runes.length * 4);
    for (var i = 0; i < runes.length; i++) {
      final cp = runes[i];
      bytes[i * 4] = (cp >> 24) & 0xFF;
      bytes[i * 4 + 1] = (cp >> 16) & 0xFF;
      bytes[i * 4 + 2] = (cp >> 8) & 0xFF;
      bytes[i * 4 + 3] = cp & 0xFF;
    }
    return SecretBytes.fromUint8List(bytes, pattern: pattern);
  }

  // ─── Lifecycle ─────────────────────────────────────────────────────────────

  /// Removes the internal reference to the [String].
  ///
  /// The [String] is NOT zeroed — only the reference is released, allowing
  /// the GC to reclaim it sooner.  See class documentation for details.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _password = null;
  }

  void _assertLive() {
    if (_disposed) throw ZeroizeDisposedError('PasswordInput');
  }

  @override
  String toString() => 'PasswordInput(${_disposed ? 'disposed' : 'live'})';
}
