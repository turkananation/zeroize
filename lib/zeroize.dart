/// Zeroize — best-effort secret memory management for pure Dart.
///
/// ## Quick Start
///
/// ```dart
/// import 'package:zeroize/zeroize.dart';
///
/// final key = SecretBytes.fromList(rawKey);
/// try {
///   final ct = encrypt(key, nonce, plaintext);
///   return ct;
/// } finally {
///   key.dispose();
/// }
/// ```
///
/// ## Security Model
///
/// This library provides **best-effort** mitigations:
///
/// - Dead Store Elimination is defeated via `@pragma('vm:never-inline')`
///   boundary functions that observably read through the buffer after each
///   overwrite pass.
/// - All comparison and tag-verification operations use branchless,
///   data-independent algorithms.
/// - [SecretBytes] attaches a [Finalizer] that zeroes the backing buffer
///   if the object is GC'd without [SecretBytes.dispose] being called.
///
/// **What it does NOT protect against:**
///
/// - GC copying — the Dart scavenging GC may copy a [Uint8List] to a new
///   heap address before zeroing.  The old copy is not zeroed.
/// - JIT timing violations — debug/profile builds use the JIT which can
///   break constant-time source-level guarantees.
/// - OS memory remanence — no `mlock`/`VirtualLock` equivalent without FFI.
///
/// **Always deploy cryptographic code as AOT release binaries:**
/// ```
/// dart compile exe
/// flutter build --release
/// ```
library;

export 'src/annotations/annotations.dart';
export 'src/config/zeroize_config.dart';
export 'src/containers/password_input.dart';
export 'src/containers/secret_box.dart';
export 'src/containers/secret_buffer.dart';
export 'src/containers/secret_bytes.dart';
export 'src/containers/secret_int_list.dart';
export 'src/core/overwrite_patterns.dart';
export 'src/core/secure_zero.dart';
export 'src/ct/ct_ops.dart';
export 'src/errors.dart';
export 'src/extensions/uint8list_extensions.dart';
export 'src/lifecycle/zeroizable.dart';
export 'src/lifecycle/zeroize_guard.dart';
export 'src/lifecycle/zeroize_scope.dart';
// dart:isolate is unavailable on web — import separately when needed:
// import 'package:zeroize/src/utils/isolate_utils.dart';
