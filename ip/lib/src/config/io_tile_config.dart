/// Direction mode for an I/O tile.
enum IODirection {
  highZ(0),
  input(1),
  output(2),
  bidir(3);

  final int value;
  const IODirection(this.value);
}

/// Configuration for an I/O tile.
///
/// Layout (8 bits):
///   [1:0] direction mode
///   [2]   input register enable
///   [3]   output register enable
///   [6:4] track select (which fabric track drives pad output)
///   [7]   reserved (pull-up enable)
class IOTileConfig {
  final IODirection direction;
  final bool inputRegEnable;
  final bool outputRegEnable;
  final int trackSelect;
  final bool pullUp;

  const IOTileConfig({
    this.direction = IODirection.highZ,
    this.inputRegEnable = false,
    this.outputRegEnable = false,
    this.trackSelect = 0,
    this.pullUp = false,
  }) : assert(trackSelect >= 0 && trackSelect < 8);

  /// Simple input pad, no register.
  static const simpleInput = IOTileConfig(direction: IODirection.input);

  /// Simple output pad, no register.
  static const simpleOutput = IOTileConfig(direction: IODirection.output);

  /// Registered input pad.
  static const registeredInput = IOTileConfig(
    direction: IODirection.input,
    inputRegEnable: true,
  );

  /// Registered output pad.
  static const registeredOutput = IOTileConfig(
    direction: IODirection.output,
    outputRegEnable: true,
  );

  static const int width = 8;

  BigInt encode() =>
      BigInt.from(direction.value) |
      (BigInt.from(inputRegEnable ? 1 : 0) << 2) |
      (BigInt.from(outputRegEnable ? 1 : 0) << 3) |
      (BigInt.from(trackSelect) << 4) |
      (BigInt.from(pullUp ? 1 : 0) << 7);

  static IOTileConfig decode(BigInt bits) {
    int field(int offset, int w) =>
        ((bits >> offset) & BigInt.from((1 << w) - 1)).toInt();

    return IOTileConfig(
      direction: IODirection.values[field(0, 2)],
      inputRegEnable: field(2, 1) == 1,
      outputRegEnable: field(3, 1) == 1,
      trackSelect: field(4, 3),
      pullUp: field(7, 1) == 1,
    );
  }

  @override
  String toString() =>
      'IOTileConfig($direction, '
      'inReg: $inputRegEnable, outReg: $outputRegEnable, '
      'track: $trackSelect, pullUp: $pullUp)';
}
