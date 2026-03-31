import 'clb_config.dart';

/// Input source for CLB input muxes and route muxes.
enum InputSource {
  north(0),
  east(1),
  south(2),
  west(3),
  clbOut(4),
  constZero(5),
  constOne(6);

  final int value;
  const InputSource(this.value);
}

/// Configuration for a routing tile.
class TileConfig {
  final ClbConfig clb;
  final InputSource sel0;
  final InputSource sel1;
  final InputSource sel2;
  final InputSource sel3;
  final bool enNorth;
  final bool enEast;
  final bool enSouth;
  final bool enWest;
  final InputSource selNorth;
  final InputSource selEast;
  final InputSource selSouth;
  final InputSource selWest;

  const TileConfig({
    this.clb = const ClbConfig(),
    this.sel0 = InputSource.constZero,
    this.sel1 = InputSource.constZero,
    this.sel2 = InputSource.constZero,
    this.sel3 = InputSource.constZero,
    this.enNorth = false,
    this.enEast = false,
    this.enSouth = false,
    this.enWest = false,
    this.selNorth = InputSource.north,
    this.selEast = InputSource.east,
    this.selSouth = InputSource.south,
    this.selWest = InputSource.west,
  });

  static const int width = 46;

  BigInt encode() {
    var bits = clb.encode();
    bits |= BigInt.from(sel0.value) << 18;
    bits |= BigInt.from(sel1.value) << 21;
    bits |= BigInt.from(sel2.value) << 24;
    bits |= BigInt.from(sel3.value) << 27;
    bits |= BigInt.from(enNorth ? 1 : 0) << 30;
    bits |= BigInt.from(enEast ? 1 : 0) << 31;
    bits |= BigInt.from(enSouth ? 1 : 0) << 32;
    bits |= BigInt.from(enWest ? 1 : 0) << 33;
    bits |= BigInt.from(selNorth.value) << 34;
    bits |= BigInt.from(selEast.value) << 37;
    bits |= BigInt.from(selSouth.value) << 40;
    bits |= BigInt.from(selWest.value) << 43;
    return bits;
  }

  static TileConfig decode(BigInt bits) {
    int field(int offset, int w) =>
        ((bits >> offset) & BigInt.from((1 << w) - 1)).toInt();

    InputSource src(int offset) => InputSource.values[field(offset, 3)];

    return TileConfig(
      clb: ClbConfig.decode(bits),
      sel0: src(18),
      sel1: src(21),
      sel2: src(24),
      sel3: src(27),
      enNorth: field(30, 1) == 1,
      enEast: field(31, 1) == 1,
      enSouth: field(32, 1) == 1,
      enWest: field(33, 1) == 1,
      selNorth: src(34),
      selEast: src(37),
      selSouth: src(40),
      selWest: src(43),
    );
  }

  @override
  String toString() =>
      'TileConfig(clb: $clb, '
      'inputs: [$sel0, $sel1, $sel2, $sel3], '
      'en: [N:$enNorth, E:$enEast, S:$enSouth, W:$enWest], '
      'routes: [N:$selNorth, E:$selEast, S:$selSouth, W:$selWest])';
}
