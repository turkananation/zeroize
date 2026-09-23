import 'dart:typed_data';

import '../config/zeroize_config.dart';
import '../core/overwrite_patterns.dart';
import '../core/secure_zero.dart';

/// Secure-zeroing convenience methods on [Uint8List].
extension Uint8ListZeroize on Uint8List {
  /// Overwrites [this] in-place using [pattern].
  void secureZeroize({ZeroizePattern? pattern}) =>
      secureZero(this, pattern: pattern ?? ZeroizeConfig.defaultPattern);

  /// Returns a new [Uint8List] that is the element-wise XOR of [this] and
  /// [other].  Both lists MUST have the same length.
  Uint8List xorWith(Uint8List other) {
    assert(length == other.length, 'xorWith: length mismatch');
    final result = Uint8List(length);
    for (var i = 0; i < length; i++) {
      result[i] = this[i] ^ other[i];
    }
    return result;
  }

  /// Returns `true` iff every byte is `0x00`.
  bool get isAllZero {
    var acc = 0;
    for (final b in this) {
      acc |= b;
    }
    return acc == 0;
  }

  /// Returns a lowercase hex string.
  ///
  /// Safe for logging **non-secret** debug data.  Never call on material
  /// that should remain secret.
  String toHexString() {
    final buf = StringBuffer();
    for (final b in this) {
      buf.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return buf.toString();
  }
}

/// Secure-zeroing convenience methods on [List<int>].
extension ListIntZeroize on List<int> {
  /// Overwrites [this] in-place using [pattern].
  void secureZeroize({ZeroizePattern? pattern}) =>
      secureZeroIntList(
        this,
        pattern: pattern ?? ZeroizeConfig.defaultPattern,
      );
}
