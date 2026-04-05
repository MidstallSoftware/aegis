import 'package:rohd/rohd.dart';
import 'package:rohd_hcl/rohd_hcl.dart';

/// Streams configuration bits into the FPGA fabric config chain.
class FabricConfigLoader extends Module {
  Logic get clk => input('clk');
  Logic get start => input('start');

  Logic get done => output('done');

  Logic get cfgIn => output('cfgIn');
  Logic get cfgLoad => output('cfgLoad');

  final int totalBits;

  FabricConfigLoader(
    Logic clk,
    Logic start,
    this.totalBits,
    DataPortInterface readPort,
  ) : super(name: 'fabric_config_loader') {
    clk = addInput('clk', clk);
    start = addInput('start', start);

    addOutput('done');
    addOutput('cfgIn');
    addOutput('cfgLoad');

    readPort = readPort.clone()
      ..connectIO(
        this,
        readPort,
        inputTags: {DataPortGroup.data},
        outputTags: {DataPortGroup.control},
        uniquify: (orig) => 'rd_$orig',
      );

    final wordWidth = readPort.data.width;
    final wordsNeeded = (totalBits + wordWidth - 1) ~/ wordWidth;

    final active = Logic(name: 'active');
    final wordAddr = Logic(width: readPort.addr.width, name: 'wordAddr');
    final wordBuf = Logic(width: wordWidth, name: 'wordBuf');
    final bitIdx = Logic(width: wordWidth.bitLength, name: 'bitIdx');
    final totalShifted = Logic(
      width: totalBits.bitLength,
      name: 'totalShifted',
    );
    final shifting = Logic(name: 'shifting');
    final wordReady = Logic(name: 'wordReady');
    final allDone = Logic(name: 'allDone');

    Sequential(
      clk,
      [
        If(
          start,
          then: [
            active < Const(1),
            wordAddr < Const(0, width: wordAddr.width),
            bitIdx < Const(0, width: bitIdx.width),
            totalShifted < Const(0, width: totalShifted.width),
            shifting < Const(0),
            wordReady < Const(0),
            allDone < Const(0),
          ],
          orElse: [
            If(
              active & ~allDone,
              then: [
                If(
                  ~shifting & ~wordReady,
                  then: [
                    wordBuf < readPort.data,
                    wordReady < Const(1),
                    bitIdx < Const(0, width: bitIdx.width),
                  ],
                  orElse: [
                    If(
                      wordReady & ~shifting,
                      then: [shifting < Const(1)],
                      orElse: [
                        If(
                          shifting,
                          then: [
                            bitIdx < bitIdx + 1,
                            totalShifted < totalShifted + 1,
                            If(
                              totalShifted.eq(
                                Const(totalBits - 1, width: totalShifted.width),
                              ),
                              then: [
                                // All bits shifted
                                allDone < Const(1),
                                shifting < Const(0),
                              ],
                              orElse: [
                                If(
                                  bitIdx.eq(
                                    Const(wordWidth - 1, width: bitIdx.width),
                                  ),
                                  then: [
                                    // Word exhausted, fetch next
                                    shifting < Const(0),
                                    wordReady < Const(0),
                                    wordAddr < wordAddr + 1,
                                  ],
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ],
      reset: start,
      resetValues: {
        active: Const(0),
        shifting: Const(0),
        wordReady: Const(0),
        allDone: Const(0),
        wordAddr: Const(0, width: wordAddr.width),
        wordBuf: Const(0, width: wordWidth),
        bitIdx: Const(0, width: bitIdx.width),
        totalShifted: Const(0, width: totalShifted.width),
      },
    );

    readPort.en <= active & ~allDone & ~shifting & ~wordReady;
    readPort.addr <= wordAddr;

    cfgIn <= mux(shifting, wordBuf[bitIdx], Const(0));
    cfgLoad <= allDone;
    done <= allDone;
  }
}
