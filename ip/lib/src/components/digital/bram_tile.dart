import 'package:rohd/rohd.dart';
import 'tile.dart';

/// Dual-port Block RAM tile.
class BramTile extends Module {
  Logic get clk => input('clk');
  Logic get reset => input('reset');

  Logic get cfgIn => input('cfgIn');
  Logic get cfgOut => output('cfgOut');
  Logic get cfgLoad => input('cfgLoad');

  Logic get carryIn => input('carryIn');
  Logic get carryOut => output('carryOut');

  final int dataWidth;
  final int addrWidth;
  int get depth => 1 << addrWidth;

  BramTile(
    Logic clk,
    Logic reset,
    Logic cfgIn,
    Logic cfgLoad,
    TileInterface input,
    TileInterface output, {
    required Logic carryIn,
    this.dataWidth = 8,
    this.addrWidth = 7,
  }) : super(name: 'bram_tile') {
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

    // Config chain
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

    final enPortA = configReg[0];
    final enPortB = configReg[1];

    // Carry pass-through (BRAM doesn't use carry, just forwards it)
    this.carryOut <= carryIn;

    // Storage bank
    final storage = List<Logic>.generate(
      depth,
      (i) => Logic(width: dataWidth, name: 'mem_$i'),
    );

    // --- Port mapping adapted to available track width ---
    // If tracks < addrWidth + dataWidth + 1, clamp to what fits.
    final tracks = input.north.width;
    final effAddrWidth = addrWidth < tracks ? addrWidth : tracks - 1;
    final effDataWidth = (addrWidth + dataWidth) < tracks
        ? dataWidth
        : tracks - effAddrWidth - 1;
    final hasWe = (effAddrWidth + effDataWidth) < tracks;

    // --- Port A: north input, south output ---
    final aAddr = effAddrWidth > 0
        ? input.north.slice(effAddrWidth - 1, 0)
        : Const(0, width: addrWidth);
    final aWrData = effDataWidth > 0
        ? input.north.slice(effAddrWidth + effDataWidth - 1, effAddrWidth)
        : Const(0, width: dataWidth);
    final aWe = hasWe ? input.north[effAddrWidth + effDataWidth] : Const(0);

    // --- Port B: west input, east output ---
    final bAddr = effAddrWidth > 0
        ? input.west.slice(effAddrWidth - 1, 0)
        : Const(0, width: addrWidth);
    final bWrData = effDataWidth > 0
        ? input.west.slice(effAddrWidth + effDataWidth - 1, effAddrWidth)
        : Const(0, width: dataWidth);
    final bWe = hasWe ? input.west[effAddrWidth + effDataWidth] : Const(0);

    // Zero-extend address/data to full width if tracks are narrower
    final aAddrFull = aAddr.zeroExtend(addrWidth);
    final bAddrFull = bAddr.zeroExtend(addrWidth);
    final aWrDataFull = aWrData.zeroExtend(dataWidth);
    final bWrDataFull = bWrData.zeroExtend(dataWidth);

    // Synchronous write (both ports)
    Sequential(
      clk,
      [
        for (int i = 0; i < depth; i++) ...[
          If(
            enPortA & aWe & aAddrFull.eq(Const(i, width: addrWidth)),
            then: [storage[i] < aWrDataFull],
          ),
          If(
            enPortB & bWe & bAddrFull.eq(Const(i, width: addrWidth)),
            then: [storage[i] < bWrDataFull],
          ),
        ],
      ],
      reset: reset,
      resetValues: {
        for (int i = 0; i < depth; i++) storage[i]: Const(0, width: dataWidth),
      },
    );

    // Combinational read
    final rdDataA = Logic(width: dataWidth, name: 'rdDataA');
    final rdDataB = Logic(width: dataWidth, name: 'rdDataB');

    Combinational([
      rdDataA < Const(0, width: dataWidth),
      If(
        enPortA,
        then: [
          Case(aAddrFull, [
            for (int i = 0; i < depth; i++)
              CaseItem(Const(LogicValue.ofInt(i, addrWidth)), [
                rdDataA < storage[i],
              ]),
          ]),
        ],
      ),
    ]);

    Combinational([
      rdDataB < Const(0, width: dataWidth),
      If(
        enPortB,
        then: [
          Case(bAddrFull, [
            for (int i = 0; i < depth; i++)
              CaseItem(Const(LogicValue.ofInt(i, addrWidth)), [
                rdDataB < storage[i],
              ]),
          ]),
        ],
      ),
    ]);

    // Drive read data onto output tracks, zero-extend to track width
    if (dataWidth < tracks) {
      output.south <= [Const(0, width: tracks - dataWidth), rdDataA].swizzle();
      output.east <= [Const(0, width: tracks - dataWidth), rdDataB].swizzle();
    } else {
      output.south <= rdDataA.slice(tracks - 1, 0);
      output.east <= rdDataB.slice(tracks - 1, 0);
    }

    // Unused routing outputs
    output.north <= Const(0, width: tracks);
    output.west <= Const(0, width: tracks);
  }

  static const int CONFIG_WIDTH = 8;

  /// Descriptor for external tooling.
  static Map<String, dynamic> descriptor({
    required int dataWidth,
    required int addrWidth,
    required int bramColumnInterval,
    required List<int> columns,
  }) => {
    'column_interval': bramColumnInterval,
    'columns': columns,
    'data_width': bramColumnInterval > 0 ? dataWidth : null,
    'addr_width': bramColumnInterval > 0 ? addrWidth : null,
    'depth': bramColumnInterval > 0 ? (1 << addrWidth) : null,
    'tile_config_width': CONFIG_WIDTH,
  };
}
