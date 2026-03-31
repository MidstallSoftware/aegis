import 'lut4_config.dart';

/// Configuration for a Configurable Logic Block.
///
/// Layout (18 bits):
///   [15:0]  LUT truth table
///   [16]    FF enable (output registered on clock)
///   [17]    carry mode enable
class ClbConfig {
  final Lut4Config lut;
  final bool ffEnable;
  final bool carryMode;

  const ClbConfig({
    this.lut = const Lut4Config(),
    this.ffEnable = false,
    this.carryMode = false,
  });

  /// A CLB configured as a full-adder cell (carry propagate + carry chain).
  static const fullAdder = ClbConfig(
    lut: Lut4Config.carryPropagate,
    carryMode: true,
  );

  static const int width = 18;

  BigInt encode() =>
      lut.encode() |
      (BigInt.from(ffEnable ? 1 : 0) << 16) |
      (BigInt.from(carryMode ? 1 : 0) << 17);

  static ClbConfig decode(BigInt bits) => ClbConfig(
    lut: Lut4Config.decode(bits),
    ffEnable: (bits >> 16) & BigInt.one == BigInt.one,
    carryMode: (bits >> 17) & BigInt.one == BigInt.one,
  );

  @override
  String toString() => 'ClbConfig(lut: $lut, ff: $ffEnable, carry: $carryMode)';
}
