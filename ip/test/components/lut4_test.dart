import 'package:aegis_ip/aegis_ip.dart';
import 'package:rohd/rohd.dart';
import 'package:test/test.dart';

void main() {
  tearDown(() async {
    await Simulator.reset();
  });

  group('Lut4', () {
    test('AND truth table', () async {
      final cfg = Const(0x8888, width: 16);
      final in0 = Logic();
      final in1 = Logic();
      final in2 = Logic();
      final in3 = Logic();

      final lut = Lut4(cfg, in0: in0, in1: in1, in2: in2, in3: in3);
      await lut.build();

      in2.put(0);
      in3.put(0);

      in0.put(0);
      in1.put(0);
      expect(lut.out.value.toInt(), 0);

      in0.put(1);
      in1.put(0);
      expect(lut.out.value.toInt(), 0);

      in0.put(0);
      in1.put(1);
      expect(lut.out.value.toInt(), 0);

      in0.put(1);
      in1.put(1);
      expect(lut.out.value.toInt(), 1);
    });

    test('XOR truth table', () async {
      final cfg = Const(0x6666, width: 16);
      final in0 = Logic();
      final in1 = Logic();
      final in2 = Logic();
      final in3 = Logic();

      final lut = Lut4(cfg, in0: in0, in1: in1, in2: in2, in3: in3);
      await lut.build();

      in2.put(0);
      in3.put(0);

      in0.put(0);
      in1.put(0);
      expect(lut.out.value.toInt(), 0);

      in0.put(1);
      in1.put(0);
      expect(lut.out.value.toInt(), 1);

      in0.put(0);
      in1.put(1);
      expect(lut.out.value.toInt(), 1);

      in0.put(1);
      in1.put(1);
      expect(lut.out.value.toInt(), 0);
    });

    test('all-ones truth table outputs 1', () async {
      final cfg = Const(0xFFFF, width: 16);
      final in0 = Logic();
      final in1 = Logic();
      final in2 = Logic();
      final in3 = Logic();

      final lut = Lut4(cfg, in0: in0, in1: in1, in2: in2, in3: in3);
      await lut.build();

      for (int i = 0; i < 16; i++) {
        in0.put(i & 1);
        in1.put((i >> 1) & 1);
        in2.put((i >> 2) & 1);
        in3.put((i >> 3) & 1);
        expect(lut.out.value.toInt(), 1);
      }
    });

    test('all-zeros truth table outputs 0', () async {
      final cfg = Const(0x0000, width: 16);
      final in0 = Logic();
      final in1 = Logic();
      final in2 = Logic();
      final in3 = Logic();

      final lut = Lut4(cfg, in0: in0, in1: in1, in2: in2, in3: in3);
      await lut.build();

      for (int i = 0; i < 16; i++) {
        in0.put(i & 1);
        in1.put((i >> 1) & 1);
        in2.put((i >> 2) & 1);
        in3.put((i >> 3) & 1);
        expect(lut.out.value.toInt(), 0);
      }
    });

    test('exhaustive 4-input check', () async {
      const tt = 0xACE1;
      final cfg = Const(tt, width: 16);
      final in0 = Logic();
      final in1 = Logic();
      final in2 = Logic();
      final in3 = Logic();

      final lut = Lut4(cfg, in0: in0, in1: in1, in2: in2, in3: in3);
      await lut.build();

      for (int i = 0; i < 16; i++) {
        in0.put(i & 1);
        in1.put((i >> 1) & 1);
        in2.put((i >> 2) & 1);
        in3.put((i >> 3) & 1);
        expect(lut.out.value.toInt(), (tt >> i) & 1);
      }
    });
  });
}
