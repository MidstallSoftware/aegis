import 'package:rohd/rohd.dart';
import 'lut4.dart';

class Clb extends Module {
  Logic get in0 => input('in0');
  Logic get in1 => input('in1');
  Logic get in2 => input('in2');
  Logic get in3 => input('in3');

  Logic get clk => input('clk');
  Logic get cfg => input('cfg');

  Logic get carryIn => input('carryIn');
  Logic get carryOut => output('carryOut');

  Logic get out => output('out');

  Clb(
    Logic clk,
    Logic cfg, {
    required Logic in0,
    required Logic in1,
    required Logic in2,
    required Logic in3,
    required Logic carryIn,
  }) : super(name: 'clb') {
    clk = addInput('clk', clk);

    in0 = addInput('in0', in0);
    in1 = addInput('in1', in1);
    in2 = addInput('in2', in2);
    in3 = addInput('in3', in3);

    cfg = addInput('cfg', cfg, width: 18);
    carryIn = addInput('carryIn', carryIn);

    addOutput('out');
    addOutput('carryOut');

    final lutOut = Logic();

    final lut = Lut4(cfg.slice(15, 0), in0: in0, in1: in1, in2: in2, in3: in3);

    lutOut <= lut.out;

    final ffQ = Logic();

    Sequential(clk, [ffQ < lutOut]);

    final useFF = cfg[16];
    final carryMode = cfg[17];

    // Carry chain: Xilinx MUXCY style
    // LUT output = propagate (P)
    // carryOut = P ? carryIn : in0  (mux selects between propagate and generate)
    // sum = P ^ carryIn
    final carryMuxOut = Logic(name: 'carryMuxOut');
    carryMuxOut <= mux(lutOut, carryIn, in0);

    final sum = Logic(name: 'sum');
    sum <= lutOut ^ carryIn;

    // In carry mode: output = sum, carryOut = carry mux
    // In normal mode: output = LUT or FF, carryOut = 0
    carryOut <= mux(carryMode, carryMuxOut, Const(0));

    final normalOut = mux(useFF, ffQ, lutOut);
    out <= mux(carryMode, sum, normalOut);
  }
}
