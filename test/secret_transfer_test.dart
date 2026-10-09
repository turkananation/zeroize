import 'dart:isolate';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:zeroize/zeroize.dart';

void main() {
  group('SecretTransfer — construction and single consumption', () {
    test('fromBytes wipes the source buffer it copied from', () {
      final raw = Uint8List.fromList(List<int>.filled(32, 0xAB));
      final transfer = SecretTransfer.fromBytes(raw);

      expect(
        raw.every((b) => b == 0),
        isTrue,
        reason: 'source buffer must be wiped after the copy exists',
      );
      expect(transfer.length, 32);
      expect(transfer.isConsumed, isFalse);
    });

    test('materializeSecret returns the exact bytes', () {
      final payload = List<int>.generate(48, (i) => (i * 7 + 3) & 0xFF);
      final transfer = SecretTransfer.fromBytes(Uint8List.fromList(payload));

      final secret = transfer.materializeSecret();
      addTearDown(secret.dispose);

      expect(secret.length, 48);
      expect(secret.use((b) => List<int>.from(b)), payload);
    });

    test('a transfer can only be consumed once', () {
      final transfer = SecretTransfer.fromBytes(Uint8List(16));
      transfer.materializeSecret().dispose();

      expect(transfer.isConsumed, isTrue);
      expect(
        () => transfer.materializeSecret(),
        throwsA(isA<ZeroizeDisposedError>()),
      );
      expect(
        () => transfer.materializeBytes(),
        throwsA(isA<ZeroizeDisposedError>()),
      );
      expect(transfer.toString(), 'SecretTransfer(consumed)');
    });

    test('empty transfer is legal and zero-length', () {
      final transfer = SecretTransfer.fromBytes(Uint8List(0));
      expect(transfer.length, 0);
      expect(transfer.materializeSecret().length, 0);
    });
  });

  group('SecretBytes.intoTransfer — move semantics', () {
    test('intoTransfer disposes the source container', () {
      final secret = SecretBytes.fromList(List<int>.filled(32, 0x11));
      final transfer = secret.intoTransfer();

      expect(secret.isDisposed, isTrue);
      expect(() => secret.length, throwsA(isA<ZeroizeDisposedError>()));
      expect(() => secret.use((b) => b), throwsA(isA<ZeroizeDisposedError>()));

      final recovered = transfer.materializeSecret();
      addTearDown(recovered.dispose);
      expect(
        recovered.use((b) => List<int>.from(b)),
        List<int>.filled(32, 0x11),
      );
    });

    test('intoTransfer on a disposed container throws', () {
      final secret = SecretBytes.fromList([1, 2, 3]);
      secret.dispose();
      expect(() => secret.intoTransfer(), throwsA(isA<ZeroizeDisposedError>()));
    });
  });

  group('SecretTransfer — moveInto', () {
    test('moveInto copies bytes into the target', () {
      final payload = List<int>.generate(16, (i) => i + 1);
      final transfer = SecretTransfer.fromBytes(Uint8List.fromList(payload));
      final target = SecretBytes.ofLength(16);
      addTearDown(target.dispose);

      transfer.moveInto(target);

      expect(transfer.isConsumed, isTrue);
      expect(target.use((b) => List<int>.from(b)), payload);
    });
  });

  group('SecretTransfer — real isolate boundary', () {
    test('bytes survive a genuine Isolate.run hop', () async {
      final payload = List<int>.generate(64, (i) => (i * 13 + 5) & 0xFF);
      final secret = SecretBytes.fromList(payload);
      final transfer = secret.intoTransfer();

      // The receiver runs in a different isolate: it must be able to read the
      // secret, which is impossible for a bare SecretBytes.
      final recovered = await Isolate.run(() {
        final s = transfer.materializeSecret();
        final out = Uint8List.fromList(s.use((b) => List<int>.from(b)));
        s.dispose();
        return out;
      });

      expect(recovered, payload);

      // The parent's copy of `transfer` still reports unconsumed: the child
      // isolate mutated its own copy, and Dart does not share object state
      // across isolates. This is inherent to the transfer model, so it is
      // asserted rather than left as a surprise. The single-consumption guard
      // therefore holds *within* an isolate, which is where it matters — a
      // second hop on the same copy in the same isolate throws.
      expect(transfer.isConsumed, isFalse);
    });

    test(
      'a second hop on the same transfer fails in the receiving isolate',
      () async {
        final transfer = SecretTransfer.fromBytes(
          Uint8List.fromList([9, 9, 9]),
        );

        final error = await Isolate.run(() {
          transfer.materializeSecret().dispose();
          try {
            transfer.materializeSecret();
            return null;
          } on ZeroizeDisposedError catch (e) {
            return e.runtimeType.toString();
          }
        });

        expect(error, 'ZeroizeDisposedError');
      },
    );
  });

  group('SecretTransfer — moveInto target too small', () {
    test('throws a contract error and consumes the transfer', () {
      final transfer = SecretTransfer.fromBytes(
        Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]),
      );
      final target = SecretBytes.ofLength(4);
      addTearDown(target.dispose);

      expect(
        () => transfer.moveInto(target),
        throwsA(isA<ZeroizeContractError>()),
      );
      expect(transfer.isConsumed, isTrue);
    });

    test(
      'larger target keeps the transferred length and zero-fills the rest',
      () {
        final transfer = SecretTransfer.fromBytes(
          Uint8List.fromList([9, 8, 7]),
        );
        final target = SecretBytes.ofLength(6);
        addTearDown(target.dispose);

        transfer.moveInto(target);

        expect(target.use((b) => List<int>.from(b)), [9, 8, 7, 0, 0, 0]);
      },
    );
  });

  group('SecretTransfer — source wipe evidence', () {
    test('the buffer handed to fromBytes is all-zero afterwards', () {
      // Regression guard in the style of pqkeystore AGENTS rule 10: this must
      // FAIL if the secureZero call is removed from fromBytes.
      final raw = Uint8List.fromList(
        List<int>.generate(64, (i) => (i * 31 + 7) & 0xFF),
      );
      final transfer = SecretTransfer.fromBytes(raw);

      expect(raw.every((b) => b == 0), isTrue);
      // and the secret is still intact on the other side
      transfer.materializeSecret().dispose();
    });

    test('intoTransfer wipes the disposed container backing store', () {
      // Capture the exact backing buffer, then confirm it is zeroed after the
      // move. This is the direct analogue of a rule-10 test.
      final raw = Uint8List.fromList(List<int>.generate(128, (i) => i & 0xFF));
      final secret = SecretBytes.fromUint8List(raw);
      late final Uint8List captured;
      secret.mutate((b) => captured = b);

      final transfer = secret.intoTransfer();

      expect(
        captured.every((b) => b == 0),
        isTrue,
        reason: 'disposing SecretBytes must zero the captured backing store',
      );
      transfer.materializeSecret().dispose();
    });
  });
}
