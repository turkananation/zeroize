# Security Policy

## Supported Versions

| Version | Supported          |
|---------|--------------------|
| 0.1.x   | ✅ Active           |

---

## Reporting a Vulnerability

**Do not open a GitHub issue for security vulnerabilities.**

Please report security issues directly via email:

**Email:** security@turkananation.dev

Include the following in your report:

- A clear description of the vulnerability and the affected component.
- Steps to reproduce or a proof-of-concept (PoC).
- The affected version(s).
- Your assessment of severity (CVSS score if possible).
- Whether you intend to publish (and when).

### Response Timeline

| Action | Target |
|--------|--------|
| Initial acknowledgement | Within 72 hours |
| Severity assessment | Within 7 days |
| Patch for critical/high | Within 14 days |
| Coordinated disclosure | Agreed with reporter |

---

## Scope

### In Scope

- **DSE guard correctness** — `dse_guard.dart`: can the Dart AOT compiler
  eliminate writes in any tested build configuration?
- **Constant-time violations** — `ct_ops.dart`: measurable timing
  differences in `ctCompareBytes`, `ctVerifyTag`, or related functions on
  supported platforms (Dart VM AOT x64/arm64).
- **Finalizer attachment/detachment** — is the `SecretBytes` backing buffer
  always zeroed on disposal or GC?
- **`ZeroizeScope` LIFO ordering and exception safety** — are all tracked
  secrets guaranteed to be zeroed on scope exit?
- **Zeroing correctness** — does any `ZeroizePattern` leave non-zero bytes?

### Out of Scope (Acknowledged Limitations)

- GC copying leaving un-zeroed copies at old heap addresses — documented
  limitation of pure Dart.
- JIT timing violations in debug/profile builds — documented limitation.
- JavaScript/Wasm CT — documented limitation.
- OS memory remanence without `mlock` — requires FFI, out of scope.

---

## Acknowledgements

Researchers who responsibly disclose valid vulnerabilities will be credited
in [CHANGELOG.md](CHANGELOG.md) with their consent.

---

## Hall of Fame

*(empty — be the first)*
