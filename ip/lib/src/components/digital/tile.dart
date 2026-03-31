import 'package:rohd/rohd.dart';
import 'clb.dart';

enum TilePortGroup { routing }

class TileInterface extends Interface<TilePortGroup> {
  final int width;

  Logic get north => port('north');
  Logic get east => port('east');
  Logic get south => port('south');
  Logic get west => port('west');

  TileInterface({this.width = 1}) {
    setPorts(
      [
        Logic.port('north', width),
        Logic.port('east', width),
        Logic.port('south', width),
        Logic.port('west', width),
      ],
      [TilePortGroup.routing],
    );
  }

  @override
  TileInterface clone() => TileInterface(width: this.width);
}

class Tile extends Module {
  Logic get clk => input('clk');
  Logic get reset => input('reset');

  Logic get cfgIn => input('cfgIn');
  Logic get cfgOut => output('cfgOut');
  Logic get cfgLoad => input('cfgLoad');

  Logic get carryIn => input('carryIn');
  Logic get carryOut => output('carryOut');

  Tile(
    Logic clk,
    Logic reset,
    Logic cfgIn,
    Logic cfgLoad,
    TileInterface input,
    TileInterface output, {
    required Logic carryIn,
  }) : super(name: 'tile') {
    clk = addInput('clk', clk);
    reset = addInput('reset', reset);

    cfgIn = addInput('cfgIn', cfgIn, width: 1);
    cfgLoad = addInput('cfgLoad', cfgLoad, width: 1);
    addOutput('cfgOut', width: 1);

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

    final cfgOutBit = Logic(name: 'cfgOutBit');
    cfgOutBit <= shiftReg[0];
    cfgOut <= cfgOutBit;

    // Config layout (46 bits):
    //   [17:0]  CLB config (16 LUT + 1 FF enable + 1 carry mode)
    //   [20:18] sel0 (CLB in0 source)
    //   [23:21] sel1 (CLB in1 source)
    //   [26:24] sel2 (CLB in2 source)
    //   [29:27] sel3 (CLB in3 source)
    //   [30]    enable north output
    //   [31]    enable east output
    //   [32]    enable south output
    //   [33]    enable west output
    //   [36:34] selNorth (north route source)
    //   [39:37] selEast  (east route source)
    //   [42:40] selSouth (south route source)
    //   [45:43] selWest  (west route source)

    final clbConfig = configReg.slice(17, 0);

    final sel0 = configReg.slice(20, 18);
    final sel1 = configReg.slice(23, 21);
    final sel2 = configReg.slice(26, 24);
    final sel3 = configReg.slice(29, 27);

    final enNorth = configReg[30];
    final enEast = configReg[31];
    final enSouth = configReg[32];
    final enWest = configReg[33];

    final selNorth = configReg.slice(36, 34);
    final selEast = configReg.slice(39, 37);
    final selSouth = configReg.slice(42, 40);
    final selWest = configReg.slice(45, 43);

    final clbOut = Logic();

    Logic selectInput(Logic sel) {
      final result = Logic();

      final const0 = Const(0, width: 1);
      final const1 = Const(1, width: 1);

      result <=
          mux(
            sel.eq(Const(0, width: 3)),
            input.north[0],
            mux(
              sel.eq(Const(1, width: 3)),
              input.east[0],
              mux(
                sel.eq(Const(2, width: 3)),
                input.south[0],
                mux(
                  sel.eq(Const(3, width: 3)),
                  input.west[0],
                  mux(
                    sel.eq(Const(4, width: 3)),
                    clbOut,
                    mux(
                      sel.eq(Const(5, width: 3)),
                      const0,
                      mux(sel.eq(Const(6, width: 3)), const1, const0),
                    ),
                  ),
                ),
              ),
            ),
          );

      return result;
    }

    List<Logic> selectRouteVec(Logic sel) {
      final tracks = input.north.width;

      return List.generate(tracks, (i) {
        final result = Logic();

        result <=
            mux(
              sel.eq(Const(0, width: 3)),
              input.north[i],
              mux(
                sel.eq(Const(1, width: 3)),
                input.east[i],
                mux(
                  sel.eq(Const(2, width: 3)),
                  input.south[i],
                  mux(
                    sel.eq(Const(3, width: 3)),
                    input.west[i],
                    mux(sel.eq(Const(4, width: 3)), clbOut, Const(0, width: 1)),
                  ),
                ),
              ),
            );

        return result;
      });
    }

    final in0 = selectInput(sel0);
    final in1 = selectInput(sel1);
    final in2 = selectInput(sel2);
    final in3 = selectInput(sel3);

    final clb = Clb(
      clk,
      clbConfig,
      in0: in0,
      in1: in1,
      in2: in2,
      in3: in3,
      carryIn: carryIn,
    );

    clbOut <= clb.out;
    this.carryOut <= clb.carryOut;

    final routeNorth = selectRouteVec(selNorth);
    final routeEast = selectRouteVec(selEast);
    final routeSouth = selectRouteVec(selSouth);
    final routeWest = selectRouteVec(selWest);

    output.north <=
        routeNorth.reversed
            .map((b) => mux(enNorth, b, Const(0, width: 1)))
            .toList()
            .swizzle();
    output.east <=
        routeEast.reversed
            .map((b) => mux(enEast, b, Const(0, width: 1)))
            .toList()
            .swizzle();
    output.south <=
        routeSouth.reversed
            .map((b) => mux(enSouth, b, Const(0, width: 1)))
            .toList()
            .swizzle();
    output.west <=
        routeWest.reversed
            .map((b) => mux(enWest, b, Const(0, width: 1)))
            .toList()
            .swizzle();
  }

  static const int CONFIG_WIDTH = 46;
}
