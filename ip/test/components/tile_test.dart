import 'dart:async';
import 'package:aegis_ip/aegis_ip.dart';
import 'package:rohd/rohd.dart';
import 'package:test/test.dart';

void main() {
  tearDown(() async {
    await Simulator.reset();
  });

  group('Tile', () {
    test('config chain shifts bits through', () async {
      final clk = SimpleClockGenerator(10).clk;
      final reset = Logic();
      final cfgIn = Logic();
      final cfgLoad = Logic();
      final carryIn = Logic();
      final tileIn = TileInterface(width: 4);
      final tileOut = TileInterface(width: 4);

      final tile = Tile(
        clk,
        reset,
        cfgIn,
        cfgLoad,
        tileIn,
        tileOut,
        carryIn: carryIn,
      );
      await tile.build();

      unawaited(Simulator.run());

      reset.put(1);
      cfgIn.put(0);
      cfgLoad.put(0);
      carryIn.put(0);
      tileIn.north.put(0);
      tileIn.east.put(0);
      tileIn.south.put(0);
      tileIn.west.put(0);
      await clk.nextPosedge;

      reset.put(0);
      await clk.nextPosedge;

      for (int i = 0; i < Tile.CONFIG_WIDTH; i++) {
        cfgIn.put(1);
        await clk.nextPosedge;
      }

      expect(tile.cfgOut.value.toInt(), 1);

      await Simulator.endSimulation();
    });

    test('carry chain pass-through', () async {
      final clk = SimpleClockGenerator(10).clk;
      final reset = Logic();
      final cfgIn = Logic();
      final cfgLoad = Logic();
      final carryIn = Logic();
      final tileIn = TileInterface(width: 4);
      final tileOut = TileInterface(width: 4);

      final tile = Tile(
        clk,
        reset,
        cfgIn,
        cfgLoad,
        tileIn,
        tileOut,
        carryIn: carryIn,
      );
      await tile.build();

      unawaited(Simulator.run());

      reset.put(1);
      cfgIn.put(0);
      cfgLoad.put(0);
      carryIn.put(0);
      tileIn.north.put(0);
      tileIn.east.put(0);
      tileIn.south.put(0);
      tileIn.west.put(0);
      await clk.nextPosedge;
      reset.put(0);
      await clk.nextPosedge;

      expect(tile.carryOut.value.toInt(), 0);

      await Simulator.endSimulation();
    });
  });

  group('TileInterface', () {
    test('clone preserves width', () {
      final iface = TileInterface(width: 16);
      final cloned = iface.clone();
      expect(cloned.width, 16);
    });

    test('default width is 1', () {
      final iface = TileInterface();
      expect(iface.width, 1);
    });
  });
}
