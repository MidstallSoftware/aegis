import 'package:rohd/rohd.dart';
import '../../types.dart';

/// Hard SerDes transceiver, similar to Xilinx GTP/GTX or Intel GXB.
///
/// Protocol-agnostic serializer/deserializer that the fabric can configure
/// for UART, SPI, I2C, PCIe, USB, DDR, or any other serial protocol.
/// The fabric has full control over when TX/RX transfers begin, the data
/// width, clocking, bit order, and data/strobe edges.
class SerDesTile extends Module {
  Logic get clk => input('clk');
  Logic get reset => input('reset');

  Logic get cfgIn => input('cfgIn');
  Logic get cfgOut => output('cfgOut');
  Logic get cfgLoad => input('cfgLoad');

  Logic get serialIn => input('serialIn');
  Logic get serialOut => output('serialOut');
  Logic get txReady => output('txReady');
  Logic get rxValid => output('rxValid');

  Logic get fabricIn => input('fabricIn');
  Logic get fabricOut => output('fabricOut');

  final int tracks;

  SerDesTile(
    Logic clk,
    Logic reset,
    Logic cfgIn,
    Logic cfgLoad, {
    required Logic serialIn,
    required Logic fabricIn,
    required this.tracks,
  }) : super(name: 'serdes_tile') {
    clk = addInput('clk', clk);
    reset = addInput('reset', reset);

    cfgIn = addInput('cfgIn', cfgIn);
    cfgLoad = addInput('cfgLoad', cfgLoad);
    addOutput('cfgOut');

    serialIn = addInput('serialIn', serialIn);
    addOutput('serialOut');
    addOutput('txReady');
    addOutput('rxValid');

    fabricIn = addInput('fabricIn', fabricIn, width: tracks);
    addOutput('fabricOut', width: tracks);

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
    final enTx = configReg[0];
    final enRx = configReg[1];
    final txDataSel = configReg.slice(4, 2);
    final rxDataSel = configReg.slice(7, 5);
    final wordLen = configReg.slice(15, 8); // word length - 1
    final msbFirst = configReg[16];
    final txIdleHigh = configReg[17];
    final ddrMode = configReg[18];
    final clkPol = configReg[19];
    final clkDiv = configReg.slice(27, 20); // divider - 1
    final loopback = configReg[28];
    final txStrobeSel = configReg.slice(30, 29);

    // ---- Baud rate generator ----
    // Divides fabric clock by (clkDiv + 1). Produces a single-cycle tick.
    final baudCount = Logic(width: 8, name: 'baudCount');
    final baudTick = Logic(name: 'baudTick');
    final baudTickDdr = Logic(name: 'baudTickDdr');

    Sequential(
      clk,
      [
        If(
          baudCount.gte(clkDiv),
          then: [baudCount < Const(0, width: 8)],
          orElse: [baudCount < baudCount + 1],
        ),
      ],
      reset: reset,
      resetValues: {baudCount: Const(0, width: 8)},
    );

    // SDR tick at rollover, DDR tick at rollover and halfway
    final halfDiv = Logic(width: 8, name: 'halfDiv');
    halfDiv <= [Const(0, width: 1), clkDiv.slice(7, 1)].swizzle();

    baudTick <= baudCount.eq(Const(0, width: 8));
    baudTickDdr <= baudCount.eq(Const(0, width: 8)) | baudCount.eq(halfDiv);

    final activeTick = Logic(name: 'activeTick');
    activeTick <= mux(ddrMode, baudTickDdr, baudTick);

    // Apply clock polarity: invert the tick phase when clkPol=1
    // (effectively samples on opposite edge)
    final sampleTick = Logic(name: 'sampleTick');
    sampleTick <= mux(clkPol, ~activeTick & baudCount.eq(halfDiv), activeTick);

    // ---- Track selection muxes ----
    Logic selectTrack(Logic sel) {
      Logic result = Const(0);
      for (int i = tracks - 1; i >= 0; i--) {
        result = mux(sel.eq(Const(i, width: sel.width)), fabricIn[i], result);
      }
      return result;
    }

    final txDataBit = selectTrack(txDataSel);
    final txStrobe = selectTrack([Const(0, width: 1), txStrobeSel].swizzle());

    // Loopback mux: in loopback mode, RX sees our own TX
    final rxPin = Logic(name: 'rxPin');

    // ---- TX path ----
    final txShift = Logic(width: 256, name: 'txShift');
    final txCount = Logic(width: 8, name: 'txCount');
    final txActive = Logic(name: 'txActive');
    final txBitOut = Logic(name: 'txBitOut');

    Sequential(
      clk,
      [
        If(
          enTx & ~txActive & txStrobe,
          then: [
            // Load first bit and start
            txShift < [Const(0, width: 255), txDataBit].swizzle(),
            txCount < wordLen,
            txActive < Const(1),
          ],
          orElse: [
            If(
              txActive & activeTick,
              then: [
                // Shift out: LSB-first shifts right, MSB-first shifts left
                If(
                  msbFirst,
                  then: [
                    txShift <
                        [txShift.slice(254, 0), Const(0, width: 1)].swizzle(),
                  ],
                  orElse: [
                    txShift <
                        [Const(0, width: 1), txShift.slice(255, 1)].swizzle(),
                  ],
                ),
                txCount < txCount - 1,
                If(txCount.eq(Const(0, width: 8)), then: [txActive < Const(0)]),
              ],
            ),
          ],
        ),
      ],
      reset: reset,
      resetValues: {
        txShift: Const(0, width: 256),
        txCount: Const(0, width: 8),
        txActive: Const(0),
      },
    );

    // Output bit selection: MSB-first reads from top, LSB-first from bottom
    txBitOut <= mux(msbFirst, txShift[255], txShift[0]);
    serialOut <= mux(enTx & txActive, txBitOut, txIdleHigh);
    txReady <= enTx & ~txActive;

    final rxShift = Logic(width: 256, name: 'rxShift');
    final rxCount = Logic(width: 8, name: 'rxCount');
    final rxActive = Logic(name: 'rxActive');
    final rxDone = Logic(name: 'rxDone');

    rxPin <= mux(loopback, txBitOut, serialIn);

    Sequential(
      clk,
      [
        rxDone < Const(0),
        If(
          enRx & ~rxActive & sampleTick,
          then: [
            // Start receiving
            rxActive < Const(1),
            rxCount < wordLen,
            rxShift < Const(0, width: 256),
          ],
          orElse: [
            If(
              rxActive & sampleTick,
              then: [
                // Shift in: MSB-first shifts left, LSB-first shifts right
                If(
                  msbFirst,
                  then: [
                    rxShift < [rxShift.slice(254, 0), rxPin].swizzle(),
                  ],
                  orElse: [
                    rxShift < [rxPin, rxShift.slice(255, 1)].swizzle(),
                  ],
                ),
                rxCount < rxCount - 1,
                If(
                  rxCount.eq(Const(0, width: 8)),
                  then: [rxActive < Const(0), rxDone < Const(1)],
                ),
              ],
            ),
          ],
        ),
      ],
      reset: reset,
      resetValues: {
        rxShift: Const(0, width: 256),
        rxCount: Const(0, width: 8),
        rxActive: Const(0),
        rxDone: Const(0),
      },
    );

    rxValid <= rxDone;

    // ---- Fabric output: RX data + valid on selected tracks ----
    // rxDataSel track gets the latest received bit (continuously driven
    // during reception for streaming protocols, or the LSB/MSB of the
    // completed frame). The next track (rxDataSel+1 mod tracks) carries
    // the rxDone pulse.
    fabricOut <=
        List.generate(tracks, (t) {
          final bit = Logic();
          final rxOutBit = mux(msbFirst, rxShift[255], rxShift[0]);
          bit <=
              mux(
                enRx & rxDataSel.eq(Const(t, width: 3)),
                rxOutBit,
                mux(
                  enRx & rxDataSel.eq(Const((t - 1) % tracks, width: 3)),
                  rxDone,
                  Const(0),
                ),
              );
          return bit;
        }).reversed.toList().swizzle();
  }

  static const int CONFIG_WIDTH = 32;

  /// Descriptor for external tooling.
  static Map<String, dynamic> descriptor({required int count}) => {
    'count': count,
    'tile_config_width': CONFIG_WIDTH,
    'edge_assignment': List.generate(
      count,
      (i) => {
        'index': i,
        'edge': Direction.chainOrder[i % Direction.chainOrder.length].name,
      },
    ),
  };
}
