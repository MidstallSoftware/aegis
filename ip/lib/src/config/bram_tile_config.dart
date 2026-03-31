/// Configuration for a Block RAM tile.
///
/// Layout (8 bits):
///   [0]   Port A enable
///   [1]   Port B enable
///   [7:2] reserved
class BramTileConfig {
  final bool portAEnable;
  final bool portBEnable;

  const BramTileConfig({this.portAEnable = false, this.portBEnable = false});

  /// Both ports enabled.
  static const dualPort = BramTileConfig(portAEnable: true, portBEnable: true);

  /// Only port A enabled.
  static const singlePortA = BramTileConfig(portAEnable: true);

  /// Only port B enabled.
  static const singlePortB = BramTileConfig(portBEnable: true);

  static const int width = 8;

  BigInt encode() =>
      BigInt.from(portAEnable ? 1 : 0) |
      (BigInt.from(portBEnable ? 1 : 0) << 1);

  static BramTileConfig decode(BigInt bits) => BramTileConfig(
    portAEnable: bits & BigInt.one == BigInt.one,
    portBEnable: (bits >> 1) & BigInt.one == BigInt.one,
  );

  @override
  String toString() => 'BramTileConfig(A: $portAEnable, B: $portBEnable)';
}
