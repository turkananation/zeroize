# Features

## Core Features

### Multi-Pass Secure Zeroing

| API | Target | Description |
|-----|--------|-------------|
| `secureZero(Uint8List)` | Byte buffer | Overwrites with chosen pattern |
| `secureZeroIntList(List<int>)` | Int list | For NTT polynomial arrays |
| `secureZeroRange(Uint8List, offset, count)` | Sub-region | Partial zeroing via sublistView |

#### Overwrite Patterns (`ZeroizePattern`)

| Pattern | Passes | Description |
|---------|--------|-------------|
| `zero` | 1 | Single `0x00` pass (NIST SP 800-88 Rev 1) |
| `ones` | 1 | Single `0xFF` pass |
| `twoPass` | 2 | **Default** — `0xFF` then `0x00` |
| `dod` | 3 | `0x00 · 0xFF · 0x00` (DoD 5220.22-M adapted) |
| `pseudoRandom` | 2 | Random bytes then `0x00` |
| `gutmann7` | 7 | `0x00 · 0xFF · 0xAA · 0x55 · rnd · 0xFF · 0x00` |

---

### DSE-Resistant Zeroing Engine

Dead Store Elimination in Dart AOT is defeated via:
- `@pragma('vm:never-inline')` boundary functions that observably read
  through the buffer after every pass.
- A package-level mutable sink variable (`_dseOpaqueSink`) with 32-bit
  rotate-left mixing between passes to prevent XOR-cancellation analysis.

---

### Secure Containers

#### `SecretBytes`

- Wraps a `Uint8List` — never exposes the backing buffer directly.
- All access via `use(fn)` (read-only) and `mutate(fn)` (read/write).
- `Finalizer` for GC-triggered backstop zeroing.
- Allocate-and-track in debug builds via `ZeroizeConfig`.
- Operations: `xorWith`, `fill`, `subrange`, `concat`, `generate`.
- CT comparison: `timingSafeEquals`, `timingSafeEqualsBytes`.
- Multiple `ZeroizePattern` options per instance.

#### `SecretIntList`

- Same pattern as `SecretBytes` but for `List<int>`.
- Designed for NTT polynomial coefficient arrays.
- `Finalizer` for GC-triggered backstop zeroing.
- Operations: `[]`, `[]=`, `use`, `mutate`, `fill`.

#### `SecretBuffer`

- Incremental byte accumulator (like a `BytesBuilder` for secrets).
- Zeroes the old allocation on every internal growth/realloc.
- `seal()` atomically transfers to `SecretBytes` and zeroes self.
- Prevents intermediate expansions from leaving partial key material.

#### `SecretBox<T>`

- Generic opaque wrapper for any type `T`.
- Caller-supplied zero callback for full flexibility.
- `use(fn)` / `mutate(fn)` access model.

#### `PasswordInput`

- Honest wrapper acknowledging Dart `String` immutability limitations.
- `toUtf8SecretBytes()` — produces a zeroable UTF-8 byte representation.
- `toCodePointsBytes()` — produces big-endian 32-bit code-point encoding.
- Documents byte-collection alternative via `SecretBuffer` for maximum assurance.

---

### Constant-Time Primitives (`ct_ops.dart`)

#### Byte-Sequence Comparison
- `ctCompareBytes(Uint8List, Uint8List)` — full-scan CT comparison
- `ctEquals(Uint8List, Uint8List)` — bool variant
- `ctCompareIntLists(List<int>, List<int>)` — for polynomial arrays
- `ctEqualsIntLists(List<int>, List<int>)` — bool variant
- `ctVerifyTag(Uint8List, Uint8List)` — AEAD/MAC tag verification with dummy scan on length mismatch

#### Integer Selection
- `ctSelect(condition, ifOne, ifZero)` — branchless int select
- `ctSelectByte(condition, ifOne, ifZero)` — byte-masked variant

#### Buffer Operations
- `ctConditionalCopy(condition, dst, src)` — branchless copy
- `ctConditionalSwap(condition, a, b)` — branchless swap using XOR delta

#### Integer Predicates
- `ctLessThan` / `ctGreaterThan` / `ctLessOrEqual` / `ctGreaterOrEqual`
- `ctIntEquals` / `ctIsZero` / `ctIsNonZero`

#### Integer Arithmetic
- `ctAbs` — branchless absolute value
- `ctClamp` — branchless clamp to [min, max]

#### Modular Arithmetic (ML-KEM / ML-DSA)
- `ctReduceOnce(v, mod)` — single conditional subtract into [0, mod)
- `ctLiftToPositive(v, mod)` — single conditional add from negative range
- `ctConditionalAdd(condition, v, mod)`
- `ctConditionalSub(condition, v, mod)`

---

### Lifecycle Management

#### `Zeroizable` Mixin
- `zeroize()` — must-implement, idempotent
- `useAndZeroize(fn)` — sync: run fn, then unconditionally zeroize
- `useAndZeroizeAsync(fn)` — async variant

#### `ZeroizeScope`
- RAII scope tracking multiple `Zeroizable` instances.
- LIFO disposal order.
- `run(fn)` — synchronous factory runner.
- `runAsync(fn)` — async factory runner.
- Catches individual zeroize failures so all secrets are attempted.

#### Guard Functions
- `withZeroizedBytes(data, fn)` — scoped zeroing for `Uint8List` temporaries.
- `withZeroizedBytesAsync(data, fn)` — async variant.
- `withZeroized(secrets, fn)` — LIFO zeroing for multiple `Zeroizable`.
- `withZeroizedAsync(secrets, fn)` — async variant.

---

### Extension Methods

#### `Uint8List`
- `.secureZeroize({pattern})` — inline zero
- `.xorWith(Uint8List)` — element-wise XOR returning new buffer
- `.isAllZero` — bool property
- `.toHexString()` — lowercase hex for debug logging

#### `List<int>`
- `.secureZeroize({pattern})` — inline zero

---

### Configuration

#### `ZeroizeConfig`
- `defaultPattern` / `setDefaultPattern(pattern)` — global pattern setting
- `liveSecretCount` — live `SecretBytes` instances (debug builds only)
- `totalAllocated` — total allocated since isolate start (debug builds only)
- `debugAssertNoLeaks()` — asserts all `SecretBytes` are disposed (debug only)

---

### Annotations

- `@sensitive` — marks fields/params holding secret material
- `@constantTime` — marks functions requiring CT implementation

---

### Platform Support

| Platform | Zeroing | Constant-Time |
|----------|---------|---------------|
| Dart VM (AOT release) | ✅ Best-effort | ✅ Source-level CT |
| Flutter Android/iOS (release) | ✅ Best-effort | ✅ Source-level CT |
| Flutter macOS/Windows/Linux (release) | ✅ Best-effort | ✅ Source-level CT |
| Dart VM (JIT debug/profile) | ✅ Best-effort | ⚠️ No CT guarantee |
| Dart-to-JavaScript (web) | ✅ Best-effort | ❌ No CT guarantee |
| Dart-to-Wasm | ✅ Best-effort | ❌ No CT guarantee |
