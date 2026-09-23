# Contributing

Thank you for your interest in contributing to `zeroize`.  Because this is
a security library used in post-quantum cryptographic applications, we hold
contributions to a higher bar than typical packages.

---

## Before You Start

1. **Open an issue first** for any non-trivial change — a new API, a
   behavioural change, or a security-related fix.  This avoids duplicated
   effort and lets us align on design before code is written.

2. **Security issues must not be reported as public issues.**  Use the
   responsible disclosure process in [SECURITY.md](../SECURITY.md).

---

## Development Setup

```sh
git clone https://github.com/turkananation/zeroize.git
cd zeroize
dart pub get
dart analyze
dart test
```

All three commands must pass clean before submitting a PR.

---

## Code Standards

### Style

- Follow the [Effective Dart](https://dart.dev/guides/language/effective-dart)
  style guide.
- Run `dart format .` before committing.  No unformatted code is merged.
- All public APIs require complete doc comments (including `@param`,
  `@returns`, and at least one usage example for non-trivial functions).

### Safety Rules

These apply to every file in `lib/src/`:

1. **No `dart:ffi` or `dart:io` imports** — the package is pure Dart.
2. **No `dart:isolate` imports in `lib/`** — use only in `example/` and
   document separately.
3. **Every new `@pragma('vm:never-inline')` function must have a comment**
   explaining why it must not be inlined.
4. **No data-dependent branches on secret values** in files touched by
   CT operations.  Reviewer will check carefully.
5. **New containers must attach a `Finalizer`** as a GC backstop.
6. **New containers must call `ZeroizeConfig.trackAllocate/trackDispose`**
   in their constructor and `dispose()`.

### Constant-Time Contributions

If you add or modify a `ct*` function:

- The function MUST be marked `@constantTime`.
- The PR description MUST include a proof sketch of why the implementation
  is CT at the source level (e.g., "no branches on the input; uses
  arithmetic mask pattern ...").
- Add a comment referencing the branchless technique used (two's-complement
  mask, XOR accumulator, etc.).

---

## Testing Requirements

Every PR must:

- Add tests for all new public APIs.
- Add tests for all error paths (disposed container, contract violation).
- Verify that new zeroing code leaves memory in the all-zero state.
- Add a `tearDown(() => ZeroizeConfig.debugAssertNoLeaks())` in any new
  test file that uses `SecretBytes`.

We target 90%+ line coverage for `lib/src/`.

---

## PR Checklist

```text
□ dart format . — clean
□ dart analyze — zero warnings or errors
□ dart test — all tests pass
□ New public APIs have full doc comments
□ New CT functions have @constantTime annotation + proof sketch
□ New containers attach Finalizer + call trackAllocate/trackDispose
□ Tests cover happy path, error path, and disposal
□ CHANGELOG.md updated under [Unreleased]
□ No dart:ffi / dart:io / dart:isolate in lib/
```

---

## Commit Messages

Follow [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/):

```text
feat(containers): add SecretInt32List for SIMD-friendly NTT
fix(ct): correct ctLessThan overflow for values near 2^62
docs(api-guide): add PasswordInput byte-collection example
test(secure_zero): add gutmann7 boundary test
perf(dse_guard): switch to 32-bit rotate to avoid Mint promotion
security(ct): replace ctSelect with proven branchless variant
```

---

## Review Process

1. All PRs require at least one maintainer review.
2. Security-sensitive PRs (anything in `ct_ops.dart`, `dse_guard.dart`,
   or container lifecycle) require one maintainer reviews.
3. Maintainers may request a third-party review for cryptographic primitives.

---

## Licensing

By contributing you agree that your contributions will be licensed under
the MIT License that covers this project.
