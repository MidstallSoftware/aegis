import 'package:rohd/rohd.dart';
import '../../types.dart';

/// I/O tile that sits on the edge of the fabric.
///
/// Config register layout (8 bits):
///   [1:0] direction: 00=hi-Z, 01=input, 10=output, 11=bidir
///   [2]   input register enable
///   [3]   output register enable
///   [6:4] track select (which track drives pad output)
///   [7]   pull-up enable (reserved)
class IOTile extends Module {
  Logic get clk => input('clk');
  Logic get reset => input('reset');

  Logic get cfgIn => input('cfgIn');
  Logic get cfgOut => output('cfgOut');
  Logic get cfgLoad => input('cfgLoad');

  Logic get padIn => input('padIn');
  Logic get padOut => output('padOut');
  Logic get padOutputEnable => output('padOutputEnable');

  Logic get fabricIn => input('fabricIn');
  Logic get fabricOut => output('fabricOut');

  final int tracks;

  IOTile(
    Logic clk,
    Logic reset,
    Logic cfgIn,
    Logic cfgLoad, {
    required Logic padIn,
    required Logic fabricIn,
    required this.tracks,
  }) : super(name: 'io_tile') {
    clk = addInput('clk', clk);
    reset = addInput('reset', reset);

    cfgIn = addInput('cfgIn', cfgIn);
    cfgLoad = addInput('cfgLoad', cfgLoad);
    addOutput('cfgOut');

    padIn = addInput('padIn', padIn);
    addOutput('padOut');
    addOutput('padOutputEnable');

    fabricIn = addInput('fabricIn', fabricIn, width: tracks);
    addOutput('fabricOut', width: tracks);

    // Config chain - same pattern as Tile
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

    // Decode config
    final direction = configReg.slice(1, 0);
    final enInputReg = configReg[2];
    final enOutputReg = configReg[3];
    final trackSel = configReg.slice(6, 4);

    final isInput =
        direction.eq(Const(1, width: 2)) | direction.eq(Const(3, width: 2));
    final isOutput =
        direction.eq(Const(2, width: 2)) | direction.eq(Const(3, width: 2));

    // Input path: pad -> optional register -> fabric
    final inReg = Logic(name: 'inReg');
    Sequential(clk, [inReg < padIn]);

    final inputValue = Logic(name: 'inputValue');
    inputValue <= mux(enInputReg, inReg, padIn);

    // When in input mode, broadcast pad value onto all tracks
    // When not in input mode, drive zeros
    fabricOut <=
        List.generate(tracks, (_) {
          final bit = Logic();
          bit <= mux(isInput, inputValue, Const(0));
          return bit;
        }).reversed.toList().swizzle();

    // Output path: fabric track -> optional register -> pad
    final selectedTrack = Logic(name: 'selectedTrack');

    // Mux to select one of the fabric tracks
    Logic sel = Const(0);
    for (int i = tracks - 1; i >= 0; i--) {
      sel = mux(trackSel.eq(Const(i, width: 3)), fabricIn[i], sel);
    }
    selectedTrack <= sel;

    final outReg = Logic(name: 'outReg');
    Sequential(clk, [outReg < selectedTrack]);

    final outputValue = Logic(name: 'outputValue');
    outputValue <= mux(enOutputReg, outReg, selectedTrack);

    padOut <= mux(isOutput, outputValue, Const(0));
    padOutputEnable <= isOutput;
  }

  static const int CONFIG_WIDTH = 8;

  /// Descriptor for external tooling.
  static Map<String, dynamic> descriptor({
    required int totalPads,
    required int width,
    required int height,
  }) {
    final edgeCounts = {
      Direction.north: width,
      Direction.east: height,
      Direction.south: width,
      Direction.west: height,
    };
    final pads = <Map<String, dynamic>>[];
    int idx = 0;
    for (final dir in Direction.chainOrder) {
      for (int p = 0; p < edgeCounts[dir]!; p++) {
        pads.add({
          'index': idx++,
          'edge': dir.name,
          'position': p,
          'config_width': CONFIG_WIDTH,
        });
      }
    }
    return {
      'total_pads': totalPads,
      'tile_config_width': CONFIG_WIDTH,
      'pads': pads,
    };
  }
}
