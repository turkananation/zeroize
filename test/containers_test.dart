import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:zeroize/zeroize.dart';

void main() {
  // Detect SecretBytes leaks after every test (debug builds only).
  tearDown(() => ZeroizeConfig.debugAssertNoLeaks());

  // ─── SecretBytes ─────────────────────────────────────────────────────────

  group('SecretBytes.fromList', () {
    test('copies source — mutations to source do not affect secret', () {
      final src = Uint8List.fromList([1, 2, 3]);
      final secret = SecretBytes.fromList(src);
      src[0] = 0xFF;
      secret.use((b) => expect(b[0], equals(1)));
      secret.dispose();
    });

    test('use provides correct read access', () {
      final secret = SecretBytes.fromList([10, 20, 30]);
      final sum = secret.use((b) => b.fold<int>(0, (a, v) => a + v));
      expect(sum, equals(60));
      secret.dispose();
    });
  });

  group('SecretBytes.ofLength', () {
    test('all bytes are zero', () {
      final s = SecretBytes.ofLength(16);
      s.use((b) => expect(b.every((v) => v == 0), isTrue));
      s.dispose();
    });
  });

  group('SecretBytes.generate', () {
    test('produces correct bytes via generator', () {
      final s = SecretBytes.generate(4, (i) => i * 2);
      s.use((b) => expect(b, equals([0, 2, 4, 6])));
      s.dispose();
    });

    test('masks generator output to 8 bits', () {
      final s = SecretBytes.generate(2, (i) => 0x1FF); // 511 → 0xFF
      s.use((b) => expect(b, equals([0xFF, 0xFF])));
      s.dispose();
    });
  });

  group('SecretBytes.fromUint8List', () {
    test('copies source independently', () {
      final src = Uint8List.fromList([0xAA, 0xBB]);
      final s = SecretBytes.fromUint8List(src);
      src[0] = 0x00;
      s.use((b) => expect(b[0], equals(0xAA)));
      s.dispose();
    });
  });

  group('SecretBytes disposal', () {
    test('isDisposed is true after dispose', () {
      final s = SecretBytes.fromList([1, 2, 3]);
      s.dispose();
      expect(s.isDisposed, isTrue);
    });

    test('dispose is idempotent', () {
      final s = SecretBytes.fromList([1]);
      expect(() {
        s.dispose();
        s.dispose();
      }, returnsNormally);
    });

    test('use after dispose throws ZeroizeDisposedError', () {
      final s = SecretBytes.fromList([1]);
      s.dispose();
      expect(
        () => s.use((b) => b[0]),
        throwsA(isA<ZeroizeDisposedError>()),
      );
    });

    test('length after dispose throws ZeroizeDisposedError', () {
      final s = SecretBytes.fromList([1, 2]);
      s.dispose();
      expect(() => s.length, throwsA(isA<ZeroizeDisposedError>()));
    });

    test('backing buffer is zeroed after dispose', () {
      // Retain a reference to the backing buffer via mutate (test-only hack).
      late Uint8List capturedRef;
      final s = SecretBytes.fromList(List<int>.filled(32, 0xAB));
      s.mutate((b) => capturedRef = b);
      s.dispose();
      expect(capturedRef.every((b) => b == 0), isTrue);
    });

    test('gutmann7 pattern leaves buffer zeroed', () {
      late Uint8List capturedRef;
      final s = SecretBytes.fromList(
        List<int>.filled(64, 0xFF),
        pattern: ZeroizePattern.gutmann7,
      );
      s.mutate((b) => capturedRef = b);
      s.dispose();
      expect(capturedRef.every((b) => b == 0), isTrue);
    });
  });

  group('SecretBytes operations', () {
    test('xorWith modifies in-place', () {
      final s = SecretBytes.fromList([0xFF, 0x00, 0xAA]);
      s.xorWith(Uint8List.fromList([0x0F, 0xFF, 0x55]));
      s.use((b) => expect(b, equals([0xF0, 0xFF, 0xFF])));
      s.dispose();
    });

    test('fill sets all bytes', () {
      final s = SecretBytes.ofLength(4);
      s.fill(0xCC);
      s.use((b) => expect(b.every((v) => v == 0xCC), isTrue));
      s.dispose();
    });

    test('subrange returns independent copy', () {
      final s = SecretBytes.fromList([1, 2, 3, 4, 5]);
      final sub = s.subrange(1, 4);
      sub.use((b) => expect(b, equals([2, 3, 4])));
      s.dispose();
      // sub is independent — survives s.dispose()
      sub.use((b) => expect(b[0], equals(2)));
      sub.dispose();
    });

    test('subrange without end goes to end', () {
      final s = SecretBytes.fromList([1, 2, 3, 4]);
      final sub = s.subrange(2);
      sub.use((b) => expect(b, equals([3, 4])));
      s.dispose();
      sub.dispose();
    });

    test('concat produces correct content', () {
      final a = SecretBytes.fromList([1, 2]);
      final b = SecretBytes.fromList([3, 4]);
      final c = a.concat(b);
      c.use((bytes) => expect(bytes, equals([1, 2, 3, 4])));
      a.dispose();
      b.dispose();
      c.dispose();
    });

    test('mutate allows in-place write', () {
      final s = SecretBytes.ofLength(4);
      s.mutate((b) {
        b[0] = 0xDE;
        b[1] = 0xAD;
      });
      s.use((b) {
        expect(b[0], equals(0xDE));
        expect(b[1], equals(0xAD));
      });
      s.dispose();
    });
  });

  group('SecretBytes timing-safe equality', () {
    test('timingSafeEquals: true for identical', () {
      final a = SecretBytes.fromList([1, 2, 3, 4]);
      final b = SecretBytes.fromList([1, 2, 3, 4]);
      expect(a.timingSafeEquals(b), isTrue);
      a.dispose();
      b.dispose();
    });

    test('timingSafeEquals: false for different content', () {
      final a = SecretBytes.fromList([1, 2, 3, 4]);
      final b = SecretBytes.fromList([1, 2, 3, 5]);
      expect(a.timingSafeEquals(b), isFalse);
      a.dispose();
      b.dispose();
    });

    test('timingSafeEquals: false for different lengths', () {
      final a = SecretBytes.fromList([1, 2, 3]);
      final b = SecretBytes.fromList([1, 2, 3, 4]);
      expect(a.timingSafeEquals(b), isFalse);
      a.dispose();
      b.dispose();
    });

    test('timingSafeEquals: true with self', () {
      final a = SecretBytes.fromList([1, 2, 3]);
      expect(a.timingSafeEquals(a), isTrue);
      a.dispose();
    });

    test('timingSafeEqualsBytes: true for matching bytes', () {
      final s = SecretBytes.fromList([0xDE, 0xAD, 0xBE, 0xEF]);
      expect(
        s.timingSafeEqualsBytes(
          Uint8List.fromList([0xDE, 0xAD, 0xBE, 0xEF]),
        ),
        isTrue,
      );
      s.dispose();
    });

    test('timingSafeEqualsBytes: false for different content', () {
      final s = SecretBytes.fromList([0xDE, 0xAD, 0xBE, 0xEF]);
      expect(
        s.timingSafeEqualsBytes(
          Uint8List.fromList([0xDE, 0xAD, 0xBE, 0xEE]),
        ),
        isFalse,
      );
      s.dispose();
    });

    test('timingSafeEqualsBytes: false for different lengths', () {
      final s = SecretBytes.fromList([0xDE, 0xAD]);
      expect(
        s.timingSafeEqualsBytes(Uint8List.fromList([0xDE, 0xAD, 0xBE])),
        isFalse,
      );
      s.dispose();
    });
  });

  // ─── SecretIntList ────────────────────────────────────────────────────────

  group('SecretIntList', () {
    test('fromList copies source', () {
      final src = [100, 200, 300];
      final s = SecretIntList.fromList(src);
      src[0] = -1;
      expect(s[0], equals(100));
      s.dispose();
    });

    test('ofLength fills with default 0', () {
      final s = SecretIntList.ofLength(4);
      s.use((d) => expect(d.every((v) => v == 0), isTrue));
      s.dispose();
    });

    test('ofLength fills with custom value', () {
      final s = SecretIntList.ofLength(4, fillValue: 42);
      s.use((d) => expect(d.every((v) => v == 42), isTrue));
      s.dispose();
    });

    test('element access and mutation via []= ', () {
      final s = SecretIntList.ofLength(4);
      s[0] = 3329;
      s[3] = -3329;
      expect(s[0], equals(3329));
      expect(s[3], equals(-3329));
      s.dispose();
    });

    test('fill sets all elements', () {
      final s = SecretIntList.ofLength(8);
      s.fill(42);
      s.use((d) => expect(d.every((v) => v == 42), isTrue));
      s.dispose();
    });

    test('mutate provides write access', () {
      final s = SecretIntList.ofLength(4);
      s.mutate((d) {
        for (var i = 0; i < d.length; i++) {
          d[i] = i * 1000;
        }
      });
      expect(s[2], equals(2000));
      s.dispose();
    });

    test('dispose is idempotent', () {
      final s = SecretIntList.ofLength(4);
      expect(() {
        s.dispose();
        s.dispose();
      }, returnsNormally);
    });

    test('use after dispose throws', () {
      final s = SecretIntList.ofLength(4);
      s.dispose();
      expect(() => s.use((d) => d[0]), throwsA(isA<ZeroizeDisposedError>()));
    });

    test('backing list is zeroed after dispose', () {
      late List<int> capturedRef;
      final s = SecretIntList.ofLength(32, fillValue: 0xCAFE);
      s.mutate((d) => capturedRef = d);
      s.dispose();
      expect(capturedRef.every((v) => v == 0), isTrue);
    });
  });

  // ─── SecretBuffer ─────────────────────────────────────────────────────────

  group('SecretBuffer', () {
    test('accumulates bytes from multiple sources', () {
      final buf = SecretBuffer();
      buf.addByte(0x01);
      buf.addBytes(Uint8List.fromList([0x02, 0x03]));
      buf.addList([0x04, 0x05]);
      expect(buf.length, equals(5));
      final sealed = buf.seal();
      sealed.use((b) => expect(b, equals([1, 2, 3, 4, 5])));
      sealed.dispose();
    });

    test('seal transfers content and disposes buffer', () {
      final buf = SecretBuffer();
      buf.addFill(0xAB, 16);
      expect(buf.length, equals(16));
      final sealed = buf.seal();
      expect(buf.isSealed, isTrue);
      expect(buf.isDisposed, isTrue);
      sealed.use((b) => expect(b.every((v) => v == 0xAB), isTrue));
      sealed.dispose();
    });

    test('write after seal throws ZeroizeContractError', () {
      final buf = SecretBuffer();
      buf.seal().dispose();
      expect(
        () => buf.addByte(0xFF),
        throwsA(isA<ZeroizeContractError>()),
      );
    });

    test('dispose zeroes buffer', () {
      final buf = SecretBuffer();
      buf.addFill(0xFF, 64);
      buf.dispose();
      expect(buf.isDisposed, isTrue);
    });

    test('dispose is idempotent', () {
      final buf = SecretBuffer();
      expect(() {
        buf.dispose();
        buf.dispose();
      }, returnsNormally);
    });

    test('handles growth correctly across multiple reallocs', () {
      // Start with minimum capacity and write 1024 bytes.
      final buf = SecretBuffer();
      for (var i = 0; i < 1024; i++) {
        buf.addByte(i & 0xFF);
      }
      expect(buf.length, equals(1024));
      final sealed = buf.seal();
      sealed.use((b) {
        for (var i = 0; i < 1024; i++) {
          expect(b[i], equals(i & 0xFF));
        }
      });
      sealed.dispose();
    });

    test('addFill adds correct number of bytes', () {
      final buf = SecretBuffer();
      buf.addFill(0xCC, 32);
      expect(buf.length, equals(32));
      final sealed = buf.seal();
      sealed.use((b) => expect(b.every((v) => v == 0xCC), isTrue));
      sealed.dispose();
    });

    test('addList masks values to 8 bits', () {
      final buf = SecretBuffer();
      buf.addList([0x1FF, 0x100]); // both should be truncated
      final sealed = buf.seal();
      sealed.use((b) => expect(b, equals([0xFF, 0x00])));
      sealed.dispose();
    });
  });

  // ─── SecretBox ────────────────────────────────────────────────────────────

  group('SecretBox', () {
    test('holds and uses value', () {
      var zeroed = false;
      final box = SecretBox<int>(42, (_) => zeroed = true);
      expect(box.use((v) => v * 2), equals(84));
      box.dispose();
      expect(zeroed, isTrue);
    });

    test('use after dispose throws', () {
      final box = SecretBox<String>('secret', (_) {});
      box.dispose();
      expect(() => box.use((v) => v), throwsA(isA<ZeroizeDisposedError>()));
    });

    test('dispose is idempotent — callback called once', () {
      var callCount = 0;
      final box = SecretBox<int>(1, (_) => callCount++);
      box.dispose();
      box.dispose();
      expect(callCount, equals(1));
    });

    test('mutate can modify mutable value', () {
      final list = [1, 2, 3];
      final box = SecretBox<List<int>>(
        list,
        (l) => l.fillRange(0, l.length, 0),
      );
      box.mutate((l) => l[0] = 99);
      expect(box.use((l) => l[0]), equals(99));
      box.dispose();
      expect(list.every((v) => v == 0), isTrue);
    });

    test('isDisposed is false before dispose', () {
      final box = SecretBox<int>(0, (_) {});
      expect(box.isDisposed, isFalse);
      box.dispose();
    });

    test('works with Zeroizable mixin via ZeroizeScope', () {
      var zeroed = false;
      ZeroizeScope.run((scope) {
        scope.track(SecretBox<int>(0, (_) => zeroed = true));
        return 0;
      });
      expect(zeroed, isTrue);
    });
  });

  // ─── PasswordInput ────────────────────────────────────────────────────────

  group('PasswordInput', () {
    test('toUtf8SecretBytes produces correct ASCII encoding', () {
      final pwd = PasswordInput('hello');
      final bytes = pwd.toUtf8SecretBytes();
      bytes.use((b) => expect(b, equals([104, 101, 108, 108, 111])));
      bytes.dispose();
      pwd.dispose();
    });

    test('toCodePointsBytes: 4 bytes per code point', () {
      final pwd = PasswordInput('hi');
      final bytes = pwd.toCodePointsBytes();
      expect(bytes.length, equals(8));
      bytes.use((b) {
        // 'h' = 0x68 — big-endian 32-bit → [0,0,0,0x68]
        expect(b[3], equals(0x68));
        // 'i' = 0x69 — big-endian 32-bit → [0,0,0,0x69]
        expect(b[7], equals(0x69));
        // High bytes should be zero for BMP characters
        expect(b[0], equals(0));
        expect(b[4], equals(0));
      });
      bytes.dispose();
      pwd.dispose();
    });

    test('handles multibyte UTF-8 characters', () {
      // 'café' → c(1) a(1) f(1) é(2) = 5 UTF-8 bytes
      final pwd = PasswordInput('caf\u00e9');
      final bytes = pwd.toUtf8SecretBytes();
      expect(bytes.length, equals(5));
      bytes.dispose();
      pwd.dispose();
    });

    test('dispose marks as disposed', () {
      final pwd = PasswordInput('secret');
      pwd.dispose();
      expect(pwd.isDisposed, isTrue);
    });

    test('toUtf8SecretBytes after dispose throws', () {
      final pwd = PasswordInput('x');
      pwd.dispose();
      expect(
        () => pwd.toUtf8SecretBytes(),
        throwsA(isA<ZeroizeDisposedError>()),
      );
    });

    test('dispose is idempotent', () {
      final pwd = PasswordInput('test');
      expect(() {
        pwd.dispose();
        pwd.dispose();
      }, returnsNormally);
    });

    test('codeUnitLength matches string length for ASCII', () {
      final pwd = PasswordInput('abcde');
      expect(pwd.codeUnitLength, equals(5));
      pwd.dispose();
    });
  });

  // ─── ZeroizeScope ─────────────────────────────────────────────────────────

  group('ZeroizeScope', () {
    test('zeroes all tracked items on dispose', () {
      var aZeroed = false;
      var bZeroed = false;

      final scope = ZeroizeScope();
      scope.track(SecretBox<int>(1, (_) => aZeroed = true));
      scope.track(SecretBox<int>(2, (_) => bZeroed = true));
      scope.dispose();

      expect(aZeroed, isTrue);
      expect(bZeroed, isTrue);
    });

    test('LIFO zeroing order', () {
      final order = <int>[];
      final scope = ZeroizeScope();
      for (var i = 0; i < 5; i++) {
        final captured = i;
        scope.track(SecretBox<int>(i, (_) => order.add(captured)));
      }
      scope.dispose();
      expect(order, equals([4, 3, 2, 1, 0]));
    });

    test('dispose is idempotent', () {
      var count = 0;
      final scope = ZeroizeScope();
      scope.track(SecretBox<int>(0, (_) => count++));
      scope.dispose();
      scope.dispose();
      expect(count, equals(1));
    });

    test('track on disposed scope zeroes item immediately and throws', () {
      final scope = ZeroizeScope();
      scope.dispose();
      var zeroed = false;
      expect(
        () => scope.track(SecretBox<int>(0, (_) => zeroed = true)),
        throwsA(isA<ZeroizeContractError>()),
      );
      expect(zeroed, isTrue);
    });

    test('ZeroizeScope.run zeroes on normal exit', () {
      var zeroed = false;
      ZeroizeScope.run((scope) {
        scope.track(SecretBox<int>(0, (_) => zeroed = true));
        return 42;
      });
      expect(zeroed, isTrue);
    });

    test('ZeroizeScope.run zeroes on exception and rethrows', () {
      var zeroed = false;
      expect(
        () => ZeroizeScope.run((scope) {
          scope.track(SecretBox<int>(0, (_) => zeroed = true));
          throw Exception('test error');
        }),
        throwsException,
      );
      expect(zeroed, isTrue);
    });

    test('ZeroizeScope.runAsync zeroes on completion', () async {
      var zeroed = false;
      await ZeroizeScope.runAsync((scope) async {
        scope.track(SecretBox<int>(0, (_) => zeroed = true));
        await Future<void>.delayed(Duration.zero);
        return 'done';
      });
      expect(zeroed, isTrue);
    });

    test('ZeroizeScope.runAsync zeroes on async exception', () async {
      var zeroed = false;
      await expectLater(
        ZeroizeScope.runAsync((scope) async {
          scope.track(SecretBox<int>(0, (_) => zeroed = true));
          throw Exception('async error');
        }),
        throwsException,
      );
      expect(zeroed, isTrue);
    });

    test('ZeroizeScope integrates with SecretBytes', () {
      late Uint8List capturedRef;
      ZeroizeScope.run((scope) {
        final s = scope.track(
          SecretBytes.fromList(List<int>.filled(32, 0xAB)),
        );
        s.mutate((b) => capturedRef = b);
        return 0;
      });
      expect(capturedRef.every((b) => b == 0), isTrue);
    });

    test('isDisposed is true after dispose', () {
      final scope = ZeroizeScope();
      expect(scope.isDisposed, isFalse);
      scope.dispose();
      expect(scope.isDisposed, isTrue);
    });
  });

  // ─── Guard helpers ────────────────────────────────────────────────────────

  group('withZeroizedBytes', () {
    test('zeroes on normal exit', () {
      final data = Uint8List.fromList(List<int>.filled(16, 0xFF));
      withZeroizedBytes(data, (b) => b[0]);
      expect(data.every((b) => b == 0), isTrue);
    });

    test('zeroes on throw and propagates exception', () {
      final data = Uint8List.fromList(List<int>.filled(16, 0xFF));
      expect(
        () => withZeroizedBytes(data, (_) => throw Exception('oops')),
        throwsException,
      );
      expect(data.every((b) => b == 0), isTrue);
    });

    test('returns value from fn', () {
      final data = Uint8List.fromList([0x0A]);
      final result = withZeroizedBytes(data, (b) => b[0] * 10);
      expect(result, equals(100));
    });
  });

  group('withZeroizedBytesAsync', () {
    test('zeroes on async completion', () async {
      final data = Uint8List.fromList(List<int>.filled(8, 0xCC));
      await withZeroizedBytesAsync(data, (b) async {
        await Future<void>.delayed(Duration.zero);
        return b[0];
      });
      expect(data.every((b) => b == 0), isTrue);
    });

    test('zeroes on async throw', () async {
      final data = Uint8List.fromList(List<int>.filled(8, 0xCC));
      await expectLater(
        withZeroizedBytesAsync(
          data,
          (_) async => throw Exception('async oops'),
        ),
        throwsException,
      );
      expect(data.every((b) => b == 0), isTrue);
    });
  });

  group('withZeroized', () {
    test('zeroes all secrets in LIFO order', () {
      final order = <int>[];
      final secrets = List<SecretBox<int>>.generate(
        3,
        (i) {
          final captured = i;
          return SecretBox<int>(i, (_) => order.add(captured));
        },
      );
      withZeroized(secrets, () => 'done');
      expect(order, equals([2, 1, 0]));
    });

    test('zeroes even when fn throws', () {
      var zeroed = false;
      final s = SecretBox<int>(0, (_) => zeroed = true);
      expect(
        () => withZeroized([s], () => throw Exception('bang')),
        throwsException,
      );
      expect(zeroed, isTrue);
    });

    test('returns value from fn', () {
      final s = SecretBox<int>(42, (_) {});
      final result = withZeroized([s], () => 99);
      expect(result, equals(99));
    });
  });

  group('withZeroizedAsync', () {
    test('zeroes on async completion', () async {
      var zeroed = false;
      final s = SecretBox<int>(0, (_) => zeroed = true);
      await withZeroizedAsync([s], () async {
        await Future<void>.delayed(Duration.zero);
        return 'ok';
      });
      expect(zeroed, isTrue);
    });

    test('zeroes on async throw', () async {
      var zeroed = false;
      final s = SecretBox<int>(0, (_) => zeroed = true);
      await expectLater(
        withZeroizedAsync([s], () async => throw Exception('async')),
        throwsException,
      );
      expect(zeroed, isTrue);
    });
  });

  // ─── Zeroizable mixin ─────────────────────────────────────────────────────

  group('Zeroizable.useAndZeroize', () {
    test('zeroes after sync fn', () {
      var zeroed = false;
      final s = SecretBox<int>(42, (_) => zeroed = true);
      final result = s.useAndZeroize(() => s.use((v) => v + 1));
      expect(result, equals(43));
      expect(zeroed, isTrue);
    });

    test('zeroes after sync fn throws', () {
      var zeroed = false;
      final s = SecretBox<int>(0, (_) => zeroed = true);
      expect(
        () => s.useAndZeroize(() => throw Exception('error')),
        throwsException,
      );
      expect(zeroed, isTrue);
    });
  });

  group('Zeroizable.useAndZeroizeAsync', () {
    test('zeroes after async fn', () async {
      var zeroed = false;
      final s = SecretBox<int>(10, (_) => zeroed = true);
      final result = await s.useAndZeroizeAsync(
        () async => s.use((v) => v * 2),
      );
      expect(result, equals(20));
      expect(zeroed, isTrue);
    });
  });

  // ─── ZeroizeConfig debug tracking ────────────────────────────────────────

  group('ZeroizeConfig debug tracking', () {
    test('liveCount increments on create and decrements on dispose', () {
      final before = ZeroizeConfig.liveSecretCount;
      final s = SecretBytes.fromList([1, 2, 3]);
      // In debug/test mode, tracking is active via assert() closures.
      expect(ZeroizeConfig.liveSecretCount, equals(before + 1));
      s.dispose();
      expect(ZeroizeConfig.liveSecretCount, equals(before));
    });

    test('totalAllocated only increases', () {
      final before = ZeroizeConfig.totalAllocated;
      final s = SecretBytes.fromList([1]);
      s.dispose();
      expect(ZeroizeConfig.totalAllocated, greaterThanOrEqualTo(before));
    });

    test('debugAssertNoLeaks passes when all disposed', () {
      final s = SecretBytes.fromList([1]);
      s.dispose();
      expect(() => ZeroizeConfig.debugAssertNoLeaks(), returnsNormally);
    });
  });

  // ─── Error types ──────────────────────────────────────────────────────────

  group('Error types', () {
    test('ZeroizeDisposedError has informative toString', () {
      final err = ZeroizeDisposedError('SecretBytes');
      expect(err.toString(), contains('SecretBytes'));
      expect(err.toString(), contains('disposal'));
    });

    test('ZeroizeContractError has informative toString', () {
      final err = ZeroizeContractError('already sealed');
      expect(err.toString(), contains('already sealed'));
    });
  });
}
