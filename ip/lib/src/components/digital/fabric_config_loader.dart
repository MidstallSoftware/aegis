import 'package:rohd/rohd.dart';
import 'package:rohd_hcl/rohd_hcl.dart';

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

    // Use rohd_hcl Deserializer to collect words from memory into a
    // flat LogicArray, then a Serializer to shift them out bit-by-bit.
    final active = Logic(name: 'active');
    final wordAddr = Logic(width: readPort.addr.width, name: 'wordAddr');
    final wordCount = Logic(width: wordsNeeded.bitLength, name: 'wordCount');
    final fetchDone = Logic(name: 'fetchDone');

    // --- Word fetch FSM: reads words from memory sequentially ---
    Sequential(clk, [
      If(
        start,
        then: [
          active < Const(1),
          wordAddr < Const(0, width: wordAddr.width),
          wordCount < Const(0, width: wordCount.width),
          fetchDone < Const(0),
        ],
        orElse: [
          If(
            active & ~fetchDone,
            then: [
              wordCount < wordCount + 1,
              wordAddr < wordAddr + 1,
              If(
                wordCount.eq(Const(wordsNeeded - 1, width: wordCount.width)),
                then: [fetchDone < Const(1)],
              ),
            ],
          ),
        ],
      ),
    ]);

    readPort.en <= active & ~fetchDone;
    readPort.addr <= wordAddr;

    // --- Deserializer: collects words into a wide register ---
    final deser = Deserializer(
      readPort.data,
      wordsNeeded,
      clk: clk,
      reset: start,
      enable: active & ~fetchDone,
    );

    // --- Serializer: shifts the collected words out bit-by-bit ---
    // We need to serialize the deserialized array one bit at a time.
    // Use a simple bit counter + shift approach on the deserialized output.
    final bitCounter = Logic(width: totalBits.bitLength, name: 'bitCounter');
    final shifting = Logic(name: 'shifting');
    final shiftDone = Logic(name: 'shiftDone');

    // Flatten the deserialized array into a single wide bus
    final flatBits = Logic(width: wordsNeeded * wordWidth, name: 'flatBits');
    flatBits <=
        deser.deserialized.elements
            .map((e) => e)
            .toList()
            .reversed
            .toList()
            .swizzle();

    // Latch the flat bits when deserialization completes
    final latchedBits = Logic(
      width: wordsNeeded * wordWidth,
      name: 'latchedBits',
    );

    Sequential(
      clk,
      [
        If(
          deser.done & active,
          then: [
            latchedBits < flatBits,
            shifting < Const(1),
            bitCounter < Const(0, width: bitCounter.width),
          ],
          orElse: [
            If(
              shifting,
              then: [
                bitCounter < bitCounter + 1,
                If(
                  bitCounter.eq(Const(totalBits - 1, width: bitCounter.width)),
                  then: [shifting < Const(0), shiftDone < Const(1)],
                ),
              ],
            ),
          ],
        ),
      ],
      reset: start,
      resetValues: {
        shifting: Const(0),
        shiftDone: Const(0),
        bitCounter: Const(0, width: bitCounter.width),
        latchedBits: Const(0, width: latchedBits.width),
      },
    );

    cfgIn <= mux(shifting, latchedBits[bitCounter], Const(0));
    cfgLoad <= shiftDone;
    done <= shiftDone & ~active;
  }
}
