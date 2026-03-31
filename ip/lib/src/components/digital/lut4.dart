import 'package:rohd/rohd.dart';

class Lut4 extends Module {
  Logic get in0 => input('in0');
  Logic get in1 => input('in1');
  Logic get in2 => input('in2');
  Logic get in3 => input('in3');

  Logic get cfg => input('cfg');

  Logic get out => output('out');

  Lut4(
    Logic cfg, {
    required Logic in0,
    required Logic in1,
    required Logic in2,
    required Logic in3,
  }) : super(name: 'lut4') {
    in0 = addInput('in0', in0);
    in1 = addInput('in1', in1);
    in2 = addInput('in2', in2);
    in3 = addInput('in3', in3);

    cfg = addInput('cfg', cfg, width: 16);

    addOutput('out');

    final s0 = List.generate(8, (_) => Logic());

    for (int i = 0; i < 8; i++) {
      s0[i] <= mux(in0, cfg[2 * i + 1], cfg[2 * i]);
    }

    final s1 = List.generate(4, (_) => Logic());

    for (int i = 0; i < 4; i++) {
      s1[i] <= mux(in1, s0[2 * i + 1], s0[2 * i]);
    }

    final s2 = List.generate(2, (_) => Logic());

    for (int i = 0; i < 2; i++) {
      s2[i] <= mux(in2, s1[2 * i + 1], s1[2 * i]);
    }

    out <= mux(in3, s2[1], s2[0]);
  }
}
