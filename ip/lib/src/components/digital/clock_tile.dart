import 'package:rohd/rohd.dart';

/// Clock management tile - digital PLL/MMCM equivalent.
///
/// Takes a reference clock and produces up to 4 derived clock outputs
/// with independent configurable divide ratios and phase offsets.
/// Similar in concept to Xilinx MMCM / Intel ALTPLL.
class ClockTile extends Module {
  Logic get refClk => input('refClk');
  Logic get reset => input('reset');

  Logic get cfgIn => input('cfgIn');
  Logic get cfgOut => output('cfgOut');
  Logic get cfgLoad => input('cfgLoad');

  Logic get clkOut => output('clkOut');
  Logic get locked => output('locked');

  static const int numOutputs = 4;

  ClockTile(Logic refClk, Logic reset, Logic cfgIn, Logic cfgLoad)
    : super(name: 'clock_tile') {
    refClk = addInput('refClk', refClk);
    reset = addInput('reset', reset);

    cfgIn = addInput('cfgIn', cfgIn);
    cfgLoad = addInput('cfgLoad', cfgLoad);
    addOutput('cfgOut');

    addOutput('clkOut', width: numOutputs);
    addOutput('locked');

    // Config chain
    final shiftReg = Logic(width: CONFIG_WIDTH, name: 'shiftReg');
    final configReg = Logic(width: CONFIG_WIDTH, name: 'configReg');

    Sequential(
      refClk,
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

    // Decode config
    final globalEnable = configReg[0];

    final dividers = <Logic>[];
    final phases = <Logic>[];
    final enables = <Logic>[];
    final duties = <Logic>[];

    for (int i = 0; i < numOutputs; i++) {
      dividers.add(configReg.slice(8 + i * 8, 1 + i * 8));
      phases.add(configReg.slice(34 + i * 2, 33 + i * 2));
      enables.add(configReg[41 + i]);
      duties.add(configReg[45 + i]);
    }

    // Generate clock outputs
    final clkBits = <Logic>[];
    final lockedBits = <Logic>[];

    for (int i = 0; i < numOutputs; i++) {
      final count = Logic(width: 8, name: 'count_$i');
      final clkReg = Logic(name: 'clkReg_$i');
      final cycleComplete = Logic(name: 'cycleComplete_$i');

      // Divider counter: counts from 0 to divider value
      // Phase offset: delays the start by (phase * (divider+1) / 4) cycles
      final halfDiv = Logic(width: 8, name: 'halfDiv_$i');
      halfDiv <= [Const(0, width: 1), dividers[i].slice(7, 1)].swizzle();

      // Quarter-period for phase calculation
      final quarterDiv = Logic(width: 8, name: 'quarterDiv_$i');
      quarterDiv <= [Const(0, width: 2), dividers[i].slice(7, 2)].swizzle();

      // Phase offset in cycles
      final phaseOffset = Logic(width: 8, name: 'phaseOffset_$i');
      Combinational([
        Case(
          phases[i],
          [
            CaseItem(Const(0, width: 2), [phaseOffset < Const(0, width: 8)]),
            CaseItem(Const(1, width: 2), [phaseOffset < quarterDiv]),
            CaseItem(Const(2, width: 2), [phaseOffset < halfDiv]),
            CaseItem(Const(3, width: 2), [
              phaseOffset < (halfDiv + quarterDiv),
            ]),
          ],
          defaultItem: [phaseOffset < Const(0, width: 8)],
        ),
      ]);

      Sequential(
        refClk,
        [
          If(
            globalEnable & enables[i],
            then: [
              count < count + 1,
              If(
                count.gte(dividers[i]),
                then: [count < Const(0, width: 8), cycleComplete < Const(1)],
              ),

              // 50% duty: toggle at half point and at rollover
              If(
                duties[i],
                then: [
                  If(count.eq(phaseOffset), then: [clkReg < Const(1)]),
                  If(
                    count.eq(phaseOffset + halfDiv + 1),
                    then: [clkReg < Const(0)],
                  ),
                ],
                orElse: [
                  // Single-cycle pulse mode
                  If(
                    count.eq(phaseOffset),
                    then: [clkReg < Const(1)],
                    orElse: [clkReg < Const(0)],
                  ),
                ],
              ),
            ],
            orElse: [
              count < Const(0, width: 8),
              clkReg < Const(0),
              cycleComplete < Const(0),
            ],
          ),
        ],
        reset: reset,
        resetValues: {
          count: Const(0, width: 8),
          clkReg: Const(0),
          cycleComplete: Const(0),
        },
      );

      clkBits.add(clkReg);
      lockedBits.add(mux(enables[i], cycleComplete, Const(1)));
    }

    clkOut <= clkBits.reversed.toList().swizzle();

    // Locked when all enabled outputs have completed at least one cycle
    Logic allLocked = globalEnable;
    for (final l in lockedBits) {
      allLocked = allLocked & l;
    }
    locked <= allLocked;
  }

  static const int CONFIG_WIDTH = 49;

  /// Descriptor for external tooling.
  static Map<String, dynamic> descriptor({required int count}) => {
    'tile_count': count,
    'tile_config_width': CONFIG_WIDTH,
    'outputs_per_tile': numOutputs,
    'total_outputs': count * numOutputs,
  };
}
