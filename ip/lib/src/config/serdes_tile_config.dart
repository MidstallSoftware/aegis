/// Configuration for a SerDes transceiver tile.
///
/// Layout (32 bits):
///   [0]     TX enable
///   [1]     RX enable
///   [4:2]   TX data track select
///   [7:5]   RX data track select
///   [15:8]  word length minus 1 (1–256 bit frames)
///   [16]    bit order: 0 = LSB-first, 1 = MSB-first
///   [17]    TX idle level: 0 = low, 1 = high
///   [18]    clock mode: 0 = SDR, 1 = DDR
///   [19]    clock polarity: 0 = rising, 1 = falling
///   [27:20] clock divider minus 1 (1–256x)
///   [28]    loopback mode
///   [30:29] TX strobe track select
///   [31]    reserved
class SerDesTileConfig {
  final bool txEnable;
  final bool rxEnable;
  final int txDataTrack;
  final int rxDataTrack;
  final int wordLength;
  final bool msbFirst;
  final bool txIdleHigh;
  final bool ddrMode;
  final bool clockPolarity;
  final int clockDivider;
  final bool loopback;
  final int txStrobeTrack;

  const SerDesTileConfig({
    this.txEnable = false,
    this.rxEnable = false,
    this.txDataTrack = 0,
    this.rxDataTrack = 0,
    this.wordLength = 8,
    this.msbFirst = false,
    this.txIdleHigh = true,
    this.ddrMode = false,
    this.clockPolarity = false,
    this.clockDivider = 1,
    this.loopback = false,
    this.txStrobeTrack = 0,
  }) : assert(txDataTrack >= 0 && txDataTrack < 8),
       assert(rxDataTrack >= 0 && rxDataTrack < 8),
       assert(wordLength >= 1 && wordLength <= 256),
       assert(clockDivider >= 1 && clockDivider <= 256),
       assert(txStrobeTrack >= 0 && txStrobeTrack < 4);

  /// UART TX+RX at 8-N-1, idle high, LSB-first.
  static const uart8n1 = SerDesTileConfig(
    txEnable: true,
    rxEnable: true,
    wordLength: 8,
    msbFirst: false,
    txIdleHigh: true,
  );

  /// SPI-style: MSB-first, idle low, SDR.
  static const spiMaster = SerDesTileConfig(
    txEnable: true,
    rxEnable: true,
    wordLength: 8,
    msbFirst: true,
    txIdleHigh: false,
  );

  /// DDR loopback test mode.
  static const ddrLoopback = SerDesTileConfig(
    txEnable: true,
    rxEnable: true,
    wordLength: 8,
    ddrMode: true,
    loopback: true,
  );

  static const int width = 32;

  BigInt encode() {
    var bits = BigInt.zero;
    bits |= BigInt.from(txEnable ? 1 : 0);
    bits |= BigInt.from(rxEnable ? 1 : 0) << 1;
    bits |= BigInt.from(txDataTrack) << 2;
    bits |= BigInt.from(rxDataTrack) << 5;
    bits |= BigInt.from(wordLength - 1) << 8;
    bits |= BigInt.from(msbFirst ? 1 : 0) << 16;
    bits |= BigInt.from(txIdleHigh ? 1 : 0) << 17;
    bits |= BigInt.from(ddrMode ? 1 : 0) << 18;
    bits |= BigInt.from(clockPolarity ? 1 : 0) << 19;
    bits |= BigInt.from(clockDivider - 1) << 20;
    bits |= BigInt.from(loopback ? 1 : 0) << 28;
    bits |= BigInt.from(txStrobeTrack) << 29;
    return bits;
  }

  static SerDesTileConfig decode(BigInt bits) {
    int field(int offset, int w) =>
        ((bits >> offset) & BigInt.from((1 << w) - 1)).toInt();

    return SerDesTileConfig(
      txEnable: field(0, 1) == 1,
      rxEnable: field(1, 1) == 1,
      txDataTrack: field(2, 3),
      rxDataTrack: field(5, 3),
      wordLength: field(8, 8) + 1,
      msbFirst: field(16, 1) == 1,
      txIdleHigh: field(17, 1) == 1,
      ddrMode: field(18, 1) == 1,
      clockPolarity: field(19, 1) == 1,
      clockDivider: field(20, 8) + 1,
      loopback: field(28, 1) == 1,
      txStrobeTrack: field(29, 2),
    );
  }

  @override
  String toString() =>
      'SerDesTileConfig('
      'tx: $txEnable, rx: $rxEnable, '
      'word: $wordLength, ${msbFirst ? "MSB" : "LSB"}-first, '
      '${ddrMode ? "DDR" : "SDR"}, div: $clockDivider'
      '${loopback ? ", loopback" : ""})';
}
