import 'dart:isolate';
import 'dart:typed_data';

import '../config/zeroize_config.dart';
import '../core/overwrite_patterns.dart';
import '../core/secure_zero.dart';
import '../errors.dart';
import 'secret_bytes.dart';

/// A sendable handle for secret bytes that must cross an isolate boundary.
///
/// ## Why this type exists
///
/// A [SecretBytes] cannot be sent to another isolate: it holds a `Finalizer`
/// token and a non-sendable internal buffer, so passing one through
/// `Isolate.run` or a `SendPort` fails at send time. The only portable choice
/// today is to pass a plain [Uint8List] and wipe it by hand on both sides,
/// which is a discipline problem rather than a type-level guarantee.
///
/// [SecretTransfer] makes the safe pattern expressible:
///
/// ```dart
/// // Sender isolate.
/// final secret = SecretBytes.fromUint8List(rawKey);
/// final transfer = secret.intoTransfer();  // `secret` is zeroed and disposed.
/// final recovered = await Isolate.run(() => transfer.materializeSecret());
/// ```
///
/// ## Ownership
///
/// [SecretBytes.intoTransfer] **moves** the bytes: the source [SecretBytes] is
/// zeroed and disposed, so exactly one live copy of the secret exists after the
/// call. [materializeSecret] **moves** them again, zeroing the materialized
/// buffer immediately after the [SecretBytes] copy exists. At no point are two
/// long-lived copies alive.
///
/// ## What this does not do
///
/// This is best-effort erasure, not a memory-erasure guarantee:
///
/// - The buffer held inside [TransferableTypedData] is managed by the Dart
///   runtime and **cannot be overwritten by Dart code**. After
///   [materializeSecret] runs, a runtime-managed copy may persist until it is
///   collected.
/// - Garbage collection may copy any `Uint8List` to a new address before it is
///   zeroed.
/// - No `mlock` equivalent exists in pure Dart, so pages may be written to
///   swap.
///
/// Callers must still wipe every buffer they hold, on both sides of the
/// transfer. This type removes a footgun; it does not create a new guarantee.
/// The same limits apply to every other API in this package — see
/// `SecretBytes`'s Memory-Safety Contract.
///
/// ## Single consumption is per isolate
///
/// The consume-once guard lives on the object copy, and isolates do not share
/// object state. Sending one transfer to two isolates therefore yields two
/// consumable copies. Send a transfer to exactly one receiver.
final class SecretTransfer {
  SecretTransfer._(this._transferable, this._length);

  /// Builds a transfer from [data], zeroing [data] immediately.
  ///
  /// [data] is copied into the transferable buffer and then overwritten using
  /// [pattern]. Pass the buffer you were about to hand to `Isolate.run` and the
  /// copy-then-wipe step happens for you.
  static SecretTransfer fromBytes(
    Uint8List data, {
    ZeroizePattern? pattern,
  }) {
    final transfer = SecretTransfer._(
      TransferableTypedData.fromList(<Uint8List>[data]),
      data.length,
    );
    secureZero(data, pattern: pattern ?? ZeroizeConfig.defaultPattern);
    return transfer;
  }

  final TransferableTypedData _transferable;

  /// Captured at construction because [TransferableTypedData] exposes no
  /// length before it is materialized.
  final int _length;

  bool _consumed = false;

  /// Number of bytes this transfer carries.
  int get length {
    _assertLive();
    return _length;
  }

  /// Whether [materializeSecret], [materializeBytes] or [moveInto] has run.
  bool get isConsumed => _consumed;

  /// Materializes the secret as a new [SecretBytes] and consumes this transfer.
  ///
  /// The buffer returned by `materialize()` is zeroed in a `finally`, so it does
  /// not outlive the copy — [SecretBytes.fromUint8List] always copies and never
  /// takes ownership, which is the exact trap that `SecretBytes`' own
  /// documentation warns about.
  ///
  /// Safe to call only once **within one isolate**. A second call in the same
  /// isolate throws [ZeroizeDisposedError].
  ///
  /// The single-consumption guard is per-isolate-copy, not global: sending the
  /// same transfer object to two isolates gives each its own copy, and each can
  /// materialize once. Do not fan a transfer out to multiple isolates.
  SecretBytes materializeSecret({ZeroizePattern? pattern}) {
    _assertLive();
    _consumed = true;
    final effectivePattern = pattern ?? ZeroizeConfig.defaultPattern;
    final raw = _materialize();
    try {
      return SecretBytes.fromUint8List(raw, pattern: effectivePattern);
    } finally {
      // The copy above always copies, so this is the materialized buffer, not
      // the caller's data. Wipe it even if the copy throws.
      secureZero(raw, pattern: effectivePattern);
    }
  }

  /// Materializes the secret as a plain [Uint8List] and consumes this transfer.
  ///
  /// Prefer [materializeSecret] wherever possible. This exists for the cases
  /// where an API demands a bare `Uint8List`, such as a `PointyCastle` or
  /// `package:cryptography` call. **The caller owns the returned buffer and
  /// MUST wipe it** — nothing in this package can do it for you afterwards.
  Uint8List materializeBytes({ZeroizePattern? pattern}) {
    _assertLive();
    _consumed = true;
    // Handed to the caller, who owns it. Not wiped here — see the class-level
    // caveat and the method docs.
    return _materialize();
  }

  /// Moves this transfer's bytes into [target] and consumes the transfer.
  ///
  /// [target] must be at least [length] bytes long. The transferred buffer is
  /// zeroed in a `finally`, so a short [target] cannot leak it.
  void moveInto(SecretBytes target, {ZeroizePattern? pattern}) {
    _assertLive();
    _consumed = true;
    final effectivePattern = pattern ?? ZeroizeConfig.defaultPattern;
    final raw = _materialize();
    try {
      target.mutate((dst) {
        if (dst.length < raw.length) {
          throw ZeroizeContractError(
            'SecretTransfer.moveInto: target is ${dst.length} bytes but the '
            'transfer carries ${raw.length}',
          );
        }
        dst.setRange(0, raw.length, raw);
      });
    } finally {
      secureZero(raw, pattern: effectivePattern);
    }
  }

  /// Materializes the transferable buffer into a wipeable [Uint8List] view.
  ///
  /// The returned view aliases the runtime-owned buffer; callers that do not
  /// wipe it are relying on garbage collection alone. See the class-level
  /// caveat.
  Uint8List _materialize() => _transferable.materialize().asUint8List();

  void _assertLive() {
    if (_consumed) {
      throw ZeroizeDisposedError(
        'SecretTransfer has already been consumed; a transfer moves its bytes '
        'exactly once',
      );
    }
  }

  @override
  String toString() =>
      _consumed ? 'SecretTransfer(consumed)' : 'SecretTransfer($_length bytes)';
}