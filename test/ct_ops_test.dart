import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:zeroize/zeroize.dart';

void main() {
  // ─── Byte comparison ───────────────────────────────────────────────────────

  group('ctCompareBytes', () {
    test('returns 0 for identical content', () {
      expect(
        ctCompareBytes(
          Uint8List.fromList([1, 2, 3, 4]),
          Uint8List.fromList([1, 2, 3, 4]),
        ),
        equals(0),
      );
    });

    test('returns non-zero for differing byte', () {
      expect(
        ctCompareBytes(
          Uint8List.fromList([1, 2, 3, 4]),
          Uint8List.fromList([1, 2, 3, 5]),
        ),
        isNot(equals(0)),
      );
    });

    test('returns non-zero for different lengths', () {
      expect(
        ctCompareBytes(
          Uint8List.fromList([1, 2, 3]),
          Uint8List.fromList([1, 2, 3, 4]),
        ),
        isNot(equals(0)),
      );
    });

    test('returns 0 for two empty buffers', () {
      expect(ctCompareBytes(Uint8List(0), Uint8List(0)), equals(0));
    });

    test('distinguishes all-zero from all-ones', () {
      final a = Uint8List.fromList(List<int>.filled(32, 0x00));
      final b = Uint8List.fromList(List<int>.filled(32, 0xFF));
      expect(ctCompareBytes(a, b), isNot(equals(0)));
    });

    test('first-byte difference detected', () {
      final a = Uint8List.fromList([0x01, 0x00, 0x00]);
      final b = Uint8List.fromList([0x00, 0x00, 0x00]);
      expect(ctCompareBytes(a, b), isNot(equals(0)));
    });
  });

  group('ctEquals', () {
    test('true for identical', () {
      final buf = Uint8List.fromList([0xDE, 0xAD, 0xBE, 0xEF]);
      expect(ctEquals(buf, Uint8List.fromList([0xDE, 0xAD, 0xBE, 0xEF])),
          isTrue);
    });

    test('false for different content', () {
      expect(
        ctEquals(
          Uint8List.fromList([1, 2, 3]),
          Uint8List.fromList([1, 2, 4]),
        ),
        isFalse,
      );
    });

    test('false for different length', () {
      expect(
        ctEquals(Uint8List.fromList([1, 2]), Uint8List.fromList([1, 2, 3])),
        isFalse,
      );
    });
  });

  group('ctCompareIntLists', () {
    test('0 for identical', () {
      expect(ctCompareIntLists([1, 2, 3], [1, 2, 3]), equals(0));
    });
    test('non-zero for different', () {
      expect(ctCompareIntLists([1, 2, 3], [1, 2, 4]), isNot(equals(0)));
    });
    test('non-zero for different lengths', () {
      expect(ctCompareIntLists([1, 2], [1, 2, 3]), isNot(equals(0)));
    });
    test('works with negative integers', () {
      expect(ctCompareIntLists([-3329, 0, 3328], [-3329, 0, 3328]), equals(0));
      expect(
          ctCompareIntLists([-3329, 0, 3328], [-3329, 0, 3329]),
          isNot(equals(0)));
    });
  });

  // ─── Tag verification ──────────────────────────────────────────────────────

  group('ctVerifyTag', () {
    test('true for identical tags', () {
      final tag = Uint8List.fromList(List<int>.generate(32, (i) => i));
      expect(ctVerifyTag(tag, Uint8List.fromList(tag)), isTrue);
    });

    test('false for tampered last byte', () {
      final expected = Uint8List.fromList(List<int>.generate(32, (i) => i));
      final received = Uint8List.fromList(expected);
      received[31] ^= 0x01;
      expect(ctVerifyTag(expected, received), isFalse);
    });

    test('false for tampered first byte', () {
      final expected = Uint8List.fromList(List<int>.generate(32, (i) => i));
      final received = Uint8List.fromList(expected);
      received[0] ^= 0x80;
      expect(ctVerifyTag(expected, received), isFalse);
    });

    test('false for length mismatch', () {
      final a = Uint8List.fromList(List<int>.filled(32, 0xAB));
      final b = Uint8List.fromList(List<int>.filled(16, 0xAB));
      expect(ctVerifyTag(a, b), isFalse);
    });

    test('true for empty tags', () {
      expect(ctVerifyTag(Uint8List(0), Uint8List(0)), isTrue);
    });
  });

  // ─── Integer selection ─────────────────────────────────────────────────────

  group('ctSelect', () {
    test('returns ifOne on condition=1', () {
      expect(ctSelect(1, 100, 200), equals(100));
    });
    test('returns ifZero on condition=0', () {
      expect(ctSelect(0, 100, 200), equals(200));
    });
    test('works with negative values', () {
      expect(ctSelect(1, -999, 999), equals(-999));
      expect(ctSelect(0, -999, 999), equals(999));
    });
    test('works with zeros', () {
      expect(ctSelect(1, 0, 42), equals(0));
      expect(ctSelect(0, 42, 0), equals(0));
    });
  });

  group('ctSelectByte', () {
    test('selects ifOne on condition=1', () {
      expect(ctSelectByte(1, 0xAA, 0x55), equals(0xAA));
    });
    test('selects ifZero on condition=0', () {
      expect(ctSelectByte(0, 0xAA, 0x55), equals(0x55));
    });
  });

  // ─── Buffer operations ─────────────────────────────────────────────────────

  group('ctConditionalCopy', () {
    test('copies src into dst when condition=1', () {
      final dst = Uint8List.fromList([0, 0, 0, 0]);
      ctConditionalCopy(1, dst, Uint8List.fromList([1, 2, 3, 4]));
      expect(dst, equals([1, 2, 3, 4]));
    });

    test('leaves dst unchanged when condition=0', () {
      final dst = Uint8List.fromList([5, 6, 7, 8]);
      ctConditionalCopy(0, dst, Uint8List.fromList([1, 2, 3, 4]));
      expect(dst, equals([5, 6, 7, 8]));
    });
  });

  group('ctConditionalSwap', () {
    test('swaps when condition=1', () {
      final a = Uint8List.fromList([1, 2]);
      final b = Uint8List.fromList([3, 4]);
      ctConditionalSwap(1, a, b);
      expect(a, equals([3, 4]));
      expect(b, equals([1, 2]));
    });

    test('no swap when condition=0', () {
      final a = Uint8List.fromList([1, 2]);
      final b = Uint8List.fromList([3, 4]);
      ctConditionalSwap(0, a, b);
      expect(a, equals([1, 2]));
      expect(b, equals([3, 4]));
    });

    test('double swap restores original', () {
      final a = Uint8List.fromList([0xAA, 0xBB]);
      final b = Uint8List.fromList([0xCC, 0xDD]);
      ctConditionalSwap(1, a, b);
      ctConditionalSwap(1, a, b);
      expect(a, equals([0xAA, 0xBB]));
      expect(b, equals([0xCC, 0xDD]));
    });
  });

  // ─── Integer predicates ────────────────────────────────────────────────────

  group('ctLessThan', () {
    test('3 < 7 → 1', () => expect(ctLessThan(3, 7), equals(1)));
    test('7 < 3 → 0', () => expect(ctLessThan(7, 3), equals(0)));
    test('5 < 5 → 0', () => expect(ctLessThan(5, 5), equals(0)));
    test('negative: -1 < 0 → 1', () => expect(ctLessThan(-1, 0), equals(1)));
    test('negative: 0 < -1 → 0', () => expect(ctLessThan(0, -1), equals(0)));
  });

  group('ctGreaterThan', () {
    test('10 > 5 → 1', () => expect(ctGreaterThan(10, 5), equals(1)));
    test('5 > 10 → 0', () => expect(ctGreaterThan(5, 10), equals(0)));
    test('5 > 5 → 0', () => expect(ctGreaterThan(5, 5), equals(0)));
  });

  group('ctLessOrEqual', () {
    test('3 <= 3 → 1', () => expect(ctLessOrEqual(3, 3), equals(1)));
    test('3 <= 4 → 1', () => expect(ctLessOrEqual(3, 4), equals(1)));
    test('4 <= 3 → 0', () => expect(ctLessOrEqual(4, 3), equals(0)));
  });

  group('ctGreaterOrEqual', () {
    test('3 >= 3 → 1', () => expect(ctGreaterOrEqual(3, 3), equals(1)));
    test('4 >= 3 → 1', () => expect(ctGreaterOrEqual(4, 3), equals(1)));
    test('3 >= 4 → 0', () => expect(ctGreaterOrEqual(3, 4), equals(0)));
  });

  group('ctIntEquals', () {
    test('42 == 42 → 1', () => expect(ctIntEquals(42, 42), equals(1)));
    test('0 == 0 → 1', () => expect(ctIntEquals(0, 0), equals(1)));
    test('42 == 43 → 0', () => expect(ctIntEquals(42, 43), equals(0)));
    test('-1 == 1 → 0', () => expect(ctIntEquals(-1, 1), equals(0)));
    test('-1 == -1 → 1', () => expect(ctIntEquals(-1, -1), equals(1)));
  });

  group('ctIsZero / ctIsNonZero', () {
    test('ctIsZero(0) → 1', () => expect(ctIsZero(0), equals(1)));
    test('ctIsZero(1) → 0', () => expect(ctIsZero(1), equals(0)));
    test('ctIsZero(-1) → 0', () => expect(ctIsZero(-1), equals(0)));
    test('ctIsNonZero(0) → 0', () => expect(ctIsNonZero(0), equals(0)));
    test('ctIsNonZero(42) → 1', () => expect(ctIsNonZero(42), equals(1)));
    test('ctIsNonZero(-1) → 1', () => expect(ctIsNonZero(-1), equals(1)));
  });

  // ─── Integer arithmetic ────────────────────────────────────────────────────

  group('ctAbs', () {
    test('positive unchanged', () => expect(ctAbs(5), equals(5)));
    test('negative negated', () => expect(ctAbs(-5), equals(5)));
    test('zero unchanged', () => expect(ctAbs(0), equals(0)));
    test('large positive', () => expect(ctAbs(3328), equals(3328)));
    test('large negative', () => expect(ctAbs(-3328), equals(3328)));
  });

  group('ctClamp', () {
    test('value in range unchanged', () {
      expect(ctClamp(5, 0, 10), equals(5));
    });
    test('value below min clamped', () {
      expect(ctClamp(-1, 0, 10), equals(0));
    });
    test('value above max clamped', () {
      expect(ctClamp(11, 0, 10), equals(10));
    });
    test('value at min', () {
      expect(ctClamp(0, 0, 10), equals(0));
    });
    test('value at max', () {
      expect(ctClamp(10, 0, 10), equals(10));
    });
  });

  // ─── Modular arithmetic ────────────────────────────────────────────────────

  group('ctReduceOnce — ML-KEM q=3329', () {
    const q = 3329;

    test('value in [0, q) unchanged', () {
      expect(ctReduceOnce(0, q), equals(0));
      expect(ctReduceOnce(1, q), equals(1));
      expect(ctReduceOnce(3328, q), equals(3328));
    });

    test('value == q reduced to 0', () {
      expect(ctReduceOnce(3329, q), equals(0));
    });

    test('value in (q, 2q) reduced correctly', () {
      expect(ctReduceOnce(3330, q), equals(1));
      expect(ctReduceOnce(6657, q), equals(3328)); // 6657 = 2q − 1
    });
  });

  group('ctLiftToPositive — ML-KEM q=3329', () {
    const q = 3329;

    test('-1 lifted to q-1', () {
      expect(ctLiftToPositive(-1, q), equals(q - 1));
    });
    test('-(q-1) lifted to 1', () {
      expect(ctLiftToPositive(-(q - 1), q), equals(1));
    });
    test('0 unchanged', () {
      expect(ctLiftToPositive(0, q), equals(0));
    });
    test('positive unchanged', () {
      expect(ctLiftToPositive(1, q), equals(1));
      expect(ctLiftToPositive(q - 1, q), equals(q - 1));
    });
  });

  group('ctConditionalAdd / ctConditionalSub', () {
    test('ctConditionalAdd: adds mod when condition=1', () {
      expect(ctConditionalAdd(1, -1, 3329), equals(3328));
    });
    test('ctConditionalAdd: no change when condition=0', () {
      expect(ctConditionalAdd(0, 100, 3329), equals(100));
    });
    test('ctConditionalSub: subtracts mod when condition=1', () {
      expect(ctConditionalSub(1, 3330, 3329), equals(1));
    });
    test('ctConditionalSub: no change when condition=0', () {
      expect(ctConditionalSub(0, 100, 3329), equals(100));
    });
  });
}
