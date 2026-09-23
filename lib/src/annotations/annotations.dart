import 'package:meta/meta.dart';

/// Marks a class, field, parameter, or local variable as holding sensitive
/// material that MUST be zeroed via [Zeroizable.zeroize] or
/// [SecretBytes.dispose] before it leaves its containing scope.
///
/// This annotation is documentation + static-analysis aid only.
/// It does not enforce zeroing at compile time.
@Target({
  TargetKind.classType,
  TargetKind.field,
  TargetKind.parameter,
  TargetKind.localVariable,
})
final class Sensitive {
  const Sensitive();
}

/// Convenience constant for [@Sensitive].
const sensitive = Sensitive();

/// Marks a function or method as requiring constant-time implementation.
///
/// Annotated functions MUST:
/// - Use only CT primitives from `ct_ops.dart`.
/// - Avoid data-dependent branches where the condition is secret data.
/// - Be compiled in AOT release mode for timing guarantees.
///
/// The annotation is informational — it does not enforce CT at compile time.
@Target({TargetKind.function, TargetKind.method})
final class ConstantTime {
  const ConstantTime();
}

/// Convenience constant for [@ConstantTime].
const constantTime = ConstantTime();
