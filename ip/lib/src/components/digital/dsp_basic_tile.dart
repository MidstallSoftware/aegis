import 'package:rohd/rohd.dart';
import 'tile.dart';

/// Basic DSP tile - 18×18 multiply with optional accumulate.
class DspBasicTile extends Module {
  Logic get clk => input('clk');
  Logic get reset => input('reset');

  Logic get cfgIn => input('cfgIn');
  Logic get cfgOut => output('cfgOut');
  Logic get cfgLoad => input('cfgLoad');

  Logic get carryIn => input('carryIn');
  Logic get carryOut => output('carryOut');

  static const int aWidth = 18;
  static const int bWidth = 18;
  static const int resultWidth = 36;

  DspBasicTile(
    Logic clk,
    Logic reset,
    Logic cfgIn,
    Logic cfgLoad,
    TileInterface input,
    TileInterface output, {
    required Logic carryIn,
  }) : super(name: 'dsp_basic_tile') {
    clk = addInput('clk', clk);
    reset = addInput('reset', reset);

    cfgIn = addInput('cfgIn', cfgIn);
    cfgLoad = addInput('cfgLoad', cfgLoad);
    addOutput('cfgOut');

    carryIn = addInput('carryIn', carryIn);
    addOutput('carryOut');

    input = input.clone()
      ..connectIO(
        this,
        input,
        inputTags: {TilePortGroup.routing},
        outputTags: {},
        uniquify: (orig) => 'input_$orig',
      );

    output = output.clone()
      ..connectIO(
        this,
        output,
        inputTags: {},
        outputTags: {TilePortGroup.routing},
        uniquify: (orig) => 'output_$orig',
      );

    // ---- Config chain ----
    final shiftReg = Logic(width: CONFIG_WIDTH, name: 'shiftReg');
    final configReg = Logic(width: CONFIG_WIDTH, name: 'configReg');

    Sequential(
      clk,
      [
        shiftReg < [cfgIn, shiftReg.slice(CONFIG_WIDTH - 1, 1)].swizzle(),
        If.s(cfgLoad, configReg < shiftReg),
      ],
      reset: reset,
      resetValues: {
        shiftReg: Const(0, width: CONFIG_WIDTH),
        configReg: Const(0, width: CONFIG_WIDTH),
      },
    );

    cfgOut <= shiftReg[0];

    // ---- Decode config ----
    final enable = configReg[0];
    final outRegEn = configReg[1];
    final operation = configReg.slice(3, 2);
    final signedMode = configReg[4];

    // ---- Carry pass-through ----
    this.carryOut <= carryIn;

    // ---- Extract operands from routing tracks ----
    final tracks = input.north.width;

    // Operand A: north[17:0] (or full north if tracks < 18)
    final aSliceWidth = aWidth < tracks ? aWidth : tracks;
    final operandA = Logic(width: aWidth, name: 'operandA');
    if (aSliceWidth < aWidth) {
      operandA <=
          [
            Const(0, width: aWidth - aSliceWidth),
            input.north.slice(aSliceWidth - 1, 0),
          ].swizzle();
    } else {
      operandA <= input.north.slice(aWidth - 1, 0);
    }

    // Operand B: west[17:0]
    final bSliceWidth = bWidth < tracks ? bWidth : tracks;
    final operandB = Logic(width: bWidth, name: 'operandB');
    if (bSliceWidth < bWidth) {
      operandB <=
          [
            Const(0, width: bWidth - bSliceWidth),
            input.west.slice(bSliceWidth - 1, 0),
          ].swizzle();
    } else {
      operandB <= input.west.slice(bWidth - 1, 0);
    }

    // Operand C: north[tracks-1:18] zero-extended to 36 bits
    final operandC = Logic(width: resultWidth, name: 'operandC');
    if (tracks > aWidth) {
      final cBits = tracks - aWidth;
      final cSlice = input.north.slice(tracks - 1, aWidth);
      operandC <= [Const(0, width: resultWidth - cBits), cSlice].swizzle();
    } else {
      operandC <= Const(0, width: resultWidth);
    }

    final product = Logic(width: resultWidth, name: 'product');
    product <=
        operandA.zeroExtend(resultWidth) * operandB.zeroExtend(resultWidth);

    final accumulator = Logic(width: resultWidth, name: 'accumulator');
    final rawResult = Logic(width: resultWidth, name: 'rawResult');

    Combinational([
      Case(
        operation,
        [
          CaseItem(Const(0, width: 2), [rawResult < product]),
          CaseItem(Const(1, width: 2), [rawResult < (product + operandC)]),
          CaseItem(Const(2, width: 2), [rawResult < (product + accumulator)]),
        ],
        defaultItem: [rawResult < product],
      ),
    ]);

    // ---- Output register / accumulator ----
    final regResult = Logic(width: resultWidth, name: 'regResult');

    Sequential(
      clk,
      [
        If(enable, then: [accumulator < rawResult, regResult < rawResult]),
      ],
      reset: reset,
      resetValues: {
        accumulator: Const(0, width: resultWidth),
        regResult: Const(0, width: resultWidth),
      },
    );

    // Select registered or combinational output
    final dspOut = Logic(width: resultWidth, name: 'dspOut');
    dspOut <= mux(outRegEn, regResult, rawResult);

    // ---- Drive result onto south output tracks ----
    if (resultWidth < tracks) {
      output.south <=
          [
            Const(0, width: tracks - resultWidth),
            mux(enable, dspOut, Const(0, width: resultWidth)),
          ].swizzle();
    } else {
      output.south <=
          mux(enable, dspOut.slice(tracks - 1, 0), Const(0, width: tracks));
    }

    // Unused routing outputs
    output.north <= Const(0, width: tracks);
    output.east <= Const(0, width: tracks);
    output.west <= Const(0, width: tracks);
  }

  static const int CONFIG_WIDTH = 16;

  /// Descriptor for external tooling.
  static Map<String, dynamic> descriptor({
    required int dspColumnInterval,
    required List<int> columns,
  }) => {
    'column_interval': dspColumnInterval,
    'columns': columns,
    'a_width': aWidth,
    'b_width': bWidth,
    'result_width': resultWidth,
    'tile_config_width': CONFIG_WIDTH,
  };
}
