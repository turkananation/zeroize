import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:zeroize/zeroize.dart';

void main() {
  group('secureZero — patterns overwrite memory correctly', () {
    for (final pattern in ZeroizePattern.values) {
      test(pattern.name, () {
        final data = Uint8List.fromList(
          List<int>.generate(256, (i) => (i * 37 + 13) & 0xFF),
        );
        secureZero(data, pattern: pattern);
        final expectedByte = pattern == ZeroizePattern.ones ? 0xFF : 0x00;
        expect(data.every((b) => b == expectedByte), isTrue,
            reason: 'Pattern ${pattern.name} left unexpected bytes');
      });
    }
  });

  test('secureZero: empty buffer is a no-op', () {
    expect(() => secureZero(Uint8List(0)), returnsNormally);
  });

  test('secureZero: single byte', () {
    final data = Uint8List.fromList([0xFF]);
    secureZero(data);
    expect(data[0], equals(0));
  });

  test('secureZero: large buffer with gutmann7', () {
    final data = Uint8List.fromList(List<int>.filled(65536, 0xAB));
    secureZero(data, pattern: ZeroizePattern.gutmann7);
    expect(data.every((b) => b == 0), isTrue);
  });

  test('secureZero: pseudoRandom leaves final state as zero', () {
    final data = Uint8List.fromList(List<int>.filled(128, 0x55));
    secureZero(data, pattern: ZeroizePattern.pseudoRandom);
    expect(data.every((b) => b == 0), isTrue);
  });

  group('secureZeroRange', () {
    test('zeroes only the specified region', () {
      final data = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]);
      secureZeroRange(data, 2, 4); // zero bytes [2..5]
      expect(data, equals([1, 2, 0, 0, 0, 0, 7, 8]));
    });

    test('zero-count is a no-op', () {
      final data = Uint8List.fromList([1, 2, 3]);
      secureZeroRange(data, 0, 0);
      expect(data, equals([1, 2, 3]));
    });

    test('negative count is a no-op', () {
      final data = Uint8List.fromList([1, 2, 3]);
      secureZeroRange(data, 1, -1);
      expect(data, equals([1, 2, 3]));
    });

    test('single byte at the end of buffer', () {
      final data = Uint8List.fromList([1, 2, 3, 4]);
      secureZeroRange(data, 3, 1);
      expect(data, equals([1, 2, 3, 0]));
    });

    test('zeroes with explicit pattern', () {
      final data = Uint8List.fromList([0xFF, 0xFF, 0xFF, 0xFF]);
      secureZeroRange(data, 1, 2, pattern: ZeroizePattern.dod);
      expect(data, equals([0xFF, 0x00, 0x00, 0xFF]));
    });

    test('zeroes the full buffer via range', () {
      final data = Uint8List.fromList([0xFF, 0xFF, 0xFF]);
      secureZeroRange(data, 0, 3);
      expect(data.every((b) => b == 0), isTrue);
    });

    test('asserts when offset is out of bounds', () {
      final data = Uint8List.fromList([1, 2, 3]);
      expect(
        () => secureZeroRange(data, -1, 2),
        throwsA(isA<AssertionError>()),
      );
    });

    test('asserts when range exceeds buffer length', () {
      final data = Uint8List.fromList([1, 2, 3]);
      expect(
        () => secureZeroRange(data, 2, 2),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  group('secureZeroIntList', () {
    test('zeroes all elements', () {
      final data = List<int>.generate(64, (i) => i * 3329 - 1000);
      secureZeroIntList(data);
      expect(data.every((v) => v == 0), isTrue);
    });

    test('handles negative integers', () {
      final data = [-1, -100, -8380417, 8380416, 0];
      secureZeroIntList(data);
      expect(data.every((v) => v == 0), isTrue);
    });

    test('empty list is a no-op', () {
      expect(() => secureZeroIntList([]), returnsNormally);
    });

    test('all patterns zero correctly', () {
      for (final pattern in ZeroizePattern.values) {
        final data = List<int>.generate(32, (i) => i * 100);
        secureZeroIntList(data, pattern: pattern);
        final expected = pattern == ZeroizePattern.ones ? 0xFF : 0;
        expect(data.every((v) => v == expected), isTrue,
            reason: 'Pattern ${pattern.name} left unexpected elements');
      }
    });
  });

  group('Uint8List extension', () {
    test('secureZeroize zeroes in-place', () {
      final data = Uint8List.fromList([1, 2, 3]);
      data.secureZeroize();
      expect(data.every((b) => b == 0), isTrue);
    });

    test('secureZeroize with explicit pattern', () {
      final data = Uint8List.fromList([0xAB, 0xCD]);
      data.secureZeroize(pattern: ZeroizePattern.dod);
      expect(data.every((b) => b == 0), isTrue);
    });

    test('xorWith produces correct result', () {
      final a = Uint8List.fromList([0xFF, 0x00, 0xAA]);
      final b = Uint8List.fromList([0x0F, 0xFF, 0x55]);
      expect(a.xorWith(b), equals([0xF0, 0xFF, 0xFF]));
    });

    test('xorWith asserts on length mismatch', () {
      final a = Uint8List.fromList([1, 2, 3]);
      final b = Uint8List.fromList([1, 2]);
      expect(() => a.xorWith(b), throwsA(isA<AssertionError>()));
    });

    test('isAllZero: true for zero buffer', () {
      expect(Uint8List(8).isAllZero, isTrue);
    });

    test('isAllZero: false when any byte is non-zero', () {
      final buf = Uint8List(8);
      buf[4] = 1;
      expect(buf.isAllZero, isFalse);
    });

    test('toHexString produces lowercase hex', () {
      final buf = Uint8List.fromList([0xDE, 0xAD, 0xBE, 0xEF]);
      expect(buf.toHexString(), equals('deadbeef'));
    });

    test('toHexString pads single-digit hex', () {
      final buf = Uint8List.fromList([0x00, 0x0F, 0xFF]);
      expect(buf.toHexString(), equals('000fff'));
    });
  });

  group('List<int> extension', () {
    test('secureZeroize zeroes all elements', () {
      final data = [100, 200, -300, 3329];
      data.secureZeroize();
      expect(data.every((v) => v == 0), isTrue);
    });
  });

  group('ZeroizeConfig', () {
    test('setDefaultPattern is respected', () {
      ZeroizeConfig.setDefaultPattern(ZeroizePattern.dod);
      expect(ZeroizeConfig.defaultPattern, equals(ZeroizePattern.dod));
      // Reset to default for other tests.
      ZeroizeConfig.setDefaultPattern(ZeroizePattern.twoPass);
    });
  });
}
