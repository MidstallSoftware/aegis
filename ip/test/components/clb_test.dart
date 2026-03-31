import 'dart:async';
import 'package:aegis_ip/aegis_ip.dart';
import 'package:rohd/rohd.dart';
import 'package:test/test.dart';

void main() {
  tearDown(() async {
    await Simulator.reset();
  });

  group('CLB', () {
    test('combinational mode (no FF, no carry)', () async {
      final clk = SimpleClockGenerator(10).clk;
      final cfg = Logic(width: 18);
      final in0 = Logic();
      final in1 = Logic();
      final in2 = Logic();
      final in3 = Logic();
      final carryIn = Logic();

      final clb = Clb(
        clk,
        cfg,
        in0: in0,
        in1: in1,
        in2: in2,
        in3: in3,
        carryIn: carryIn,
      );
      await clb.build();

      cfg.put(0x8888);
      in2.put(0);
      in3.put(0);
      carryIn.put(0);

      in0.put(1);
      in1.put(1);
      expect(clb.out.value.toInt(), 1);
      expect(clb.carryOut.value.toInt(), 0);

      in0.put(1);
      in1.put(0);
      expect(clb.out.value.toInt(), 0);
    });

    test('FF mode', () async {
      final clk = SimpleClockGenerator(10).clk;
      final cfg = Logic(width: 18);
      final in0 = Logic();
      final in1 = Logic();
      final in2 = Logic();
      final in3 = Logic();
      final carryIn = Logic();

      final clb = Clb(
        clk,
        cfg,
        in0: in0,
        in1: in1,
        in2: in2,
        in3: in3,
        carryIn: carryIn,
      );
      await clb.build();

      cfg.put(0xFFFF | (1 << 16));
      in0.put(0);
      in1.put(0);
      in2.put(0);
      in3.put(0);
      carryIn.put(0);

      unawaited(Simulator.run());

      await clk.nextPosedge;
      await clk.nextPosedge;
      expect(clb.out.value.toInt(), 1);

      await Simulator.endSimulation();
    });

    test('carry mode - full adder', () async {
      final clk = SimpleClockGenerator(10).clk;
      final cfg = Logic(width: 18);
      final in0 = Logic();
      final in1 = Logic();
      final in2 = Logic();
      final in3 = Logic();
      final carryIn = Logic();

      final clb = Clb(
        clk,
        cfg,
        in0: in0,
        in1: in1,
        in2: in2,
        in3: in3,
        carryIn: carryIn,
      );
      await clb.build();

      cfg.put(0x6666 | (1 << 17));
      in2.put(0);
      in3.put(0);

      for (int a = 0; a < 2; a++) {
        for (int b = 0; b < 2; b++) {
          for (int c = 0; c < 2; c++) {
            in0.put(a);
            in1.put(b);
            carryIn.put(c);

            final expectedSum = (a ^ b ^ c);
            final p = a ^ b;
            final expectedCarry = p == 1 ? c : a;

            expect(
              clb.out.value.toInt(),
              expectedSum,
              reason: 'sum: a=$a b=$b cin=$c',
            );
            expect(
              clb.carryOut.value.toInt(),
              expectedCarry,
              reason: 'carry: a=$a b=$b cin=$c',
            );
          }
        }
      }
    });
  });
}
