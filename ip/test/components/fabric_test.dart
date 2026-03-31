import 'package:aegis_ip/aegis_ip.dart';
import 'package:rohd/rohd.dart';
import 'package:test/test.dart';

void main() {
  tearDown(() async {
    await Simulator.reset();
  });

  group('LutFabric', () {
    test('builds 2x2 fabric', () async {
      final clk = SimpleClockGenerator(10).clk;
      final reset = Logic();
      final cfgIn = Logic();
      final cfgLoad = Logic();
      final input = TileInterface(width: 4);
      final output = TileInterface(width: 4);

      final fabric = LutFabric(
        clk,
        reset,
        width: 2,
        height: 2,
        tracks: 4,
        cfgIn: cfgIn,
        cfgLoad: cfgLoad,
        input: input,
        output: output,
      );
      await fabric.build();

      expect(fabric.totalConfigBits, 2 * 2 * Tile.CONFIG_WIDTH);
    });

    test('bramColumns computed correctly', () {
      expect(LutFabric.bramColumnSet(width: 8, bramColumnInterval: 0), isEmpty);

      expect(LutFabric.bramColumnSet(width: 8, bramColumnInterval: 4), {4});

      expect(LutFabric.bramColumnSet(width: 12, bramColumnInterval: 3), {
        3,
        7,
        11,
      });
    });

    test('configBitsFor accounts for BRAM columns', () {
      final noBram = LutFabric.configBitsFor(width: 8, height: 4);
      final withBram = LutFabric.configBitsFor(
        width: 8,
        height: 4,
        bramColumnInterval: 4,
      );

      expect(withBram, lessThan(noBram));
      expect(
        noBram - withBram,
        4 * (Tile.CONFIG_WIDTH - BramTile.CONFIG_WIDTH),
      );
    });

    test('builds with BRAM columns', () async {
      final clk = SimpleClockGenerator(10).clk;
      final reset = Logic();
      final cfgIn = Logic();
      final cfgLoad = Logic();
      final input = TileInterface(width: 16);
      final output = TileInterface(width: 16);

      final fabric = LutFabric(
        clk,
        reset,
        width: 8,
        height: 2,
        tracks: 16,
        bramColumnInterval: 4,
        bramDataWidth: 8,
        bramAddrWidth: 4,
        cfgIn: cfgIn,
        cfgLoad: cfgLoad,
        input: input,
        output: output,
      );
      await fabric.build();

      expect(fabric.bramColumns, {4});
    });
  });
}
