/// Configuration for a 4-input lookup table.
///
/// The LUT truth table is a 16-bit value where bit `i` is the output
/// when the 4 inputs form the binary value `i`.
class Lut4Config {
  /// 16-bit truth table.
  final int truthTable;

  const Lut4Config({this.truthTable = 0})
    : assert(truthTable >= 0 && truthTable < (1 << 16));

  /// Creates a LUT that implements a 2-input AND on in0, in1.
  static const and2 = Lut4Config(truthTable: 0x8888);

  /// Creates a LUT that implements a 2-input OR on in0, in1.
  static const or2 = Lut4Config(truthTable: 0xEEEE);

  /// Creates a LUT that implements a 2-input XOR on in0, in1.
  static const xor2 = Lut4Config(truthTable: 0x6666);

  /// Creates a LUT that implements NOT on in0.
  static const inv = Lut4Config(truthTable: 0x5555);

  /// Creates a LUT that always outputs 0.
  static const zero = Lut4Config(truthTable: 0x0000);

  /// Creates a LUT that always outputs 1.
  static const one = Lut4Config(truthTable: 0xFFFF);

  /// Creates a LUT for carry-chain propagate: P = in0 XOR in1.
  static const carryPropagate = Lut4Config(truthTable: 0x6666);

  /// Bit width of this config.
  static const int width = 16;

  BigInt encode() => BigInt.from(truthTable);

  static Lut4Config decode(BigInt bits) =>
      Lut4Config(truthTable: (bits & BigInt.from(0xFFFF)).toInt());

  @override
  String toString() =>
      'Lut4Config(0x${truthTable.toRadixString(16).padLeft(4, '0')})';
}
