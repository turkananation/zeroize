import 'dart:typed_data';

import '../config/zeroize_config.dart';
import '../core/overwrite_patterns.dart';
import '../core/secure_zero.dart';
import '../errors.dart';
import '../lifecycle/zeroizable.dart';
import 'secret_bytes.dart';

/// A mutable byte accumulator that zeroes intermediate allocations on resize
/// and the final buffer on [seal]/[dispose].
///
/// Use when building secret material incrementally without keeping plain
/// [Uint8List] copies alive.
///
/// ```dart
/// final buf = SecretBuffer();
/// for (final block in kdfStream) buf.addBytes(block);
/// final key = buf.seal(); // buffer zeroed; caller owns key
/// try {
///   useKey(key);
/// } finally {
///   key.dispose();
/// }
/// ```
final class SecretBuffer with Zeroizable {
  static const _kMinCapacity = 64;

  Uint8List _buf;
  int _length = 0;
  bool _sealed = false;
  bool _disposed = false;
  final ZeroizePattern _pattern;

  /// Creates a [SecretBuffer] with an optional [initialCapacity].
  ///
  /// The actual allocation is at least [_kMinCapacity] bytes.
  SecretBuffer({int initialCapacity = _kMinCapacity, ZeroizePattern? pattern})
    : _buf = Uint8List(initialCapacity.clamp(_kMinCapacity, 1 << 30)),
      _pattern = pattern ?? ZeroizeConfig.defaultPattern {
    ZeroizeConfig.trackAllocateBuffer();
  }

  /// Accumulates every chunk of [stream] into a new [SecretBuffer].
  ///
  /// Each element is appended as it arrives, so the buffer never holds the whole
  /// stream twice: peak secret memory is one internal allocation plus the chunk
  /// currently being appended. Empty chunks are skipped.
  ///
  /// The returned buffer is **not** sealed — the caller owns it and must call
  /// [seal] or [dispose].
  ///
  /// If [stream] emits an error, the partially accumulated buffer is
  /// [dispose]d before the error is rethrown, so no partial secret material is
  /// left live in the heap by a failed stream.
  ///
  /// Not reentrant-safe: do not share a buffer across concurrent `add` calls.
  ///
  /// Throws whatever [stream] emits, after wiping the partial buffer.
  static Future<SecretBuffer> fromStream(
    Stream<List<int>> stream, {
    int initialCapacity = _kMinCapacity,
    ZeroizePattern? pattern,
  }) async {
    final buffer = SecretBuffer(
      initialCapacity: initialCapacity,
      pattern: pattern,
    );
    try {
      await for (final chunk in stream) {
        if (chunk.isEmpty) continue;
        buffer.addList(chunk);
      }
      return buffer;
    } catch (_) {
      // A stream that fails mid-stream leaves secret bytes accumulated here.
      // Wipe them before the error propagates.
      buffer.dispose();
      rethrow;
    }
  }

  // ─── Properties ────────────────────────────────────────────────────────────

  /// Number of bytes written so far.
  int get length => _length;

  /// Whether [seal] has been called.
  bool get isSealed => _sealed;

  /// Whether [seal] or [dispose] has been called.
  bool get isDisposed => _disposed;

  // ─── Write ─────────────────────────────────────────────────────────────────

  /// Appends a single byte, masked to `[0, 255]`.
  void addByte(int byte) {
    _assertWritable();
    _ensureCapacity(_length + 1);
    _buf[_length++] = byte & 0xFF;
  }

  /// Appends all bytes from [bytes].
  void addBytes(Uint8List bytes) {
    if (bytes.isEmpty) return;
    _assertWritable();
    _ensureCapacity(_length + bytes.length);
    _buf.setRange(_length, _length + bytes.length, bytes);
    _length += bytes.length;
  }

  /// Appends all integers from [bytes], each masked to `[0, 255]`.
  void addList(List<int> bytes) {
    if (bytes.isEmpty) return;
    _assertWritable();
    _ensureCapacity(_length + bytes.length);
    for (var i = 0; i < bytes.length; i++) {
      _buf[_length + i] = bytes[i] & 0xFF;
    }
    _length += bytes.length;
  }

  /// Appends the contents of [other] to this buffer.
  ///
  /// Copies directly into this buffer's storage — no intermediate list is
  /// allocated. [other] is **not** consumed or disposed; it remains fully
  /// usable, and its bytes are copied, so later mutation of [other] does not
  /// affect what was appended.
  ///
  /// Bytes are read through [SecretBytes.use], so no reference to [other]'s
  /// backing buffer outlives the copy.
  ///
  /// Throws [ZeroizeDisposedError] if [other] has already been disposed, and
  /// [ZeroizeContractError] if this buffer is sealed or disposed.
  void addSecretBytes(SecretBytes other) {
    other.use((bytes) {
      if (bytes.isEmpty) return;
      _assertWritable();
      _ensureCapacity(_length + bytes.length);
      _buf.setRange(_length, _length + bytes.length, bytes);
      _length += bytes.length;
    });
  }

  /// Appends [byte] repeated [count] times.
  void addFill(int byte, int count) {
    if (count <= 0) return;
    _assertWritable();
    _ensureCapacity(_length + count);
    _buf.fillRange(_length, _length + count, byte & 0xFF);
    _length += count;
  }

  // ─── Seal / dispose ────────────────────────────────────────────────────────

  /// Transfers accumulated bytes into a new [SecretBytes] and disposes
  /// this buffer.
  ///
  /// The returned [SecretBytes] owns the key material; the caller must
  /// call [SecretBytes.dispose] on it when done.
  ///
  /// This [SecretBuffer] is disposed after sealing — further writes throw
  /// [ZeroizeContractError].
  SecretBytes seal() {
    _assertWritable();
    _sealed = true;
    _disposed = true;

    // Copy the active region into SecretBytes first.
    final result = SecretBytes.fromUint8List(
      Uint8List.sublistView(_buf, 0, _length),
      pattern: _pattern,
    );

    // Zero the full internal allocation (including unused capacity).
    secureZero(_buf, pattern: _pattern);
    _length = 0;
    // Decremented only after the wipe, so the debug counter can never report
    // "no leak" for a buffer whose memory was not actually zeroed.
    ZeroizeConfig.trackDisposeBuffer();
    return result;
  }

  @override
  void zeroize() => dispose();

  /// Zeroes the internal buffer without producing a [SecretBytes].
  ///
  /// Safe to call multiple times — subsequent calls are no-ops.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    secureZero(_buf, pattern: _pattern);
    _length = 0;
    // After the wipe, and unreachable twice: `seal` sets `_disposed` before
    // this can run again, and the guard above returns early in that case.
    ZeroizeConfig.trackDisposeBuffer();
  }

  // ─── Internals ─────────────────────────────────────────────────────────────

  void _ensureCapacity(int needed) {
    if (needed <= _buf.length) return;
    final newCap = (_buf.length * 2).clamp(needed, needed * 2);
    final newBuf = Uint8List(newCap);
    newBuf.setRange(0, _length, _buf);
    // Zero the old allocation before dropping the reference.
    secureZero(_buf, pattern: _pattern);
    _buf = newBuf;
  }

  void _assertWritable() {
    if (_sealed) {
      throw ZeroizeContractError('SecretBuffer has already been sealed');
    }
    if (_disposed) throw ZeroizeDisposedError('SecretBuffer');
  }
}
