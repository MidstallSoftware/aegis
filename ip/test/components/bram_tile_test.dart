import 'dart:async';
import 'package:aegis_ip/aegis_ip.dart';
import 'package:rohd/rohd.dart';
import 'package:test/test.dart';

void main() {
  tearDown(() async {
    await Simulator.reset();
  });

  group('BramTile', () {
    test('write and read port A', () async {
      final clk = SimpleClockGenerator(10).clk;
      final reset = Logic();
      final cfgIn = Logic();
      final cfgLoad = Logic();
      final carryIn = Logic();
      final tileIn = TileInterface(width: 16);
      final tileOut = TileInterface(width: 16);

      final bram = BramTile(
        clk,
        reset,
        cfgIn,
        cfgLoad,
        tileIn,
        tileOut,
        carryIn: carryIn,
        dataWidth: 8,
        addrWidth: 4,
      );
      await bram.build();

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

      cfgIn.put(1);
      await clk.nextPosedge;
      for (int i = 1; i < BramTile.CONFIG_WIDTH; i++) {
        cfgIn.put(0);
        await clk.nextPosedge;
      }
      cfgLoad.put(1);
      await clk.nextPosedge;
      cfgLoad.put(0);
      await clk.nextPosedge;

      final writeVal = 3 | (0xAB << 4) | (1 << 12);
      tileIn.north.put(writeVal);
      await clk.nextPosedge;

      tileIn.north.put(3);
      await clk.nextPosedge;

      expect(tileOut.south.value.toInt() & 0xFF, 0xAB);

      await Simulator.endSimulation();
    });

    test('write and read port B', () async {
      final clk = SimpleClockGenerator(10).clk;
      final reset = Logic();
      final cfgIn = Logic();
      final cfgLoad = Logic();
      final carryIn = Logic();
      final tileIn = TileInterface(width: 16);
      final tileOut = TileInterface(width: 16);

      final bram = BramTile(
        clk,
        reset,
        cfgIn,
        cfgLoad,
        tileIn,
        tileOut,
        carryIn: carryIn,
        dataWidth: 8,
        addrWidth: 4,
      );
      await bram.build();

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

      cfgIn.put(0);
      await clk.nextPosedge;
      cfgIn.put(1);
      await clk.nextPosedge;
      for (int i = 2; i < BramTile.CONFIG_WIDTH; i++) {
        cfgIn.put(0);
        await clk.nextPosedge;
      }
      cfgLoad.put(1);
      await clk.nextPosedge;
      cfgLoad.put(0);
      await clk.nextPosedge;

      final writeVal = 5 | (0x77 << 4) | (1 << 12);
      tileIn.west.put(writeVal);
      await clk.nextPosedge;

      tileIn.west.put(5);
      await clk.nextPosedge;

      expect(tileOut.east.value.toInt() & 0xFF, 0x77);

      await Simulator.endSimulation();
    });

    test('carry pass-through', () async {
      final clk = SimpleClockGenerator(10).clk;
      final reset = Logic();
      final cfgIn = Logic();
      final cfgLoad = Logic();
      final carryIn = Logic();
      final tileIn = TileInterface(width: 16);
      final tileOut = TileInterface(width: 16);

      final bram = BramTile(
        clk,
        reset,
        cfgIn,
        cfgLoad,
        tileIn,
        tileOut,
        carryIn: carryIn,
        dataWidth: 8,
        addrWidth: 4,
      );
      await bram.build();

      carryIn.put(1);
      cfgIn.put(0);
      cfgLoad.put(0);
      reset.put(0);
      tileIn.north.put(0);
      tileIn.east.put(0);
      tileIn.south.put(0);
      tileIn.west.put(0);

      expect(bram.carryOut.value.toInt(), 1);
    });
  });
}
