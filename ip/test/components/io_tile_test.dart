import 'dart:async';
import 'package:aegis_ip/aegis_ip.dart';
import 'package:rohd/rohd.dart';
import 'package:test/test.dart';

void main() {
  tearDown(() async {
    await Simulator.reset();
  });

  group('IOTile', () {
    test('input mode broadcasts pad to fabric', () async {
      final clk = SimpleClockGenerator(10).clk;
      final reset = Logic();
      final cfgIn = Logic();
      final cfgLoad = Logic();
      final padIn = Logic();
      final fabricIn = Logic(width: 4);

      final tile = IOTile(
        clk,
        reset,
        cfgIn,
        cfgLoad,
        padIn: padIn,
        fabricIn: fabricIn,
        tracks: 4,
      );
      await tile.build();

      unawaited(Simulator.run());

      reset.put(1);
      cfgIn.put(0);
      cfgLoad.put(0);
      padIn.put(0);
      fabricIn.put(0);
      await clk.nextPosedge;
      reset.put(0);

      final configBits = IOTileConfig.simpleInput.encode().toInt();
      for (int i = 0; i < IOTile.CONFIG_WIDTH; i++) {
        cfgIn.put((configBits >> i) & 1);
        await clk.nextPosedge;
      }
      cfgLoad.put(1);
      await clk.nextPosedge;
      cfgLoad.put(0);
      await clk.nextPosedge;

      padIn.put(1);
      await clk.nextPosedge;

      expect(tile.fabricOut.value.toInt(), 0xF);
      expect(tile.padOutputEnable.value.toInt(), 0);

      await Simulator.endSimulation();
    });

    test('output mode drives pad from fabric track', () async {
      final clk = SimpleClockGenerator(10).clk;
      final reset = Logic();
      final cfgIn = Logic();
      final cfgLoad = Logic();
      final padIn = Logic();
      final fabricIn = Logic(width: 4);

      final tile = IOTile(
        clk,
        reset,
        cfgIn,
        cfgLoad,
        padIn: padIn,
        fabricIn: fabricIn,
        tracks: 4,
      );
      await tile.build();

      unawaited(Simulator.run());

      reset.put(1);
      cfgIn.put(0);
      cfgLoad.put(0);
      padIn.put(0);
      fabricIn.put(0);
      await clk.nextPosedge;
      reset.put(0);

      final configBits = const IOTileConfig(
        direction: IODirection.output,
        trackSelect: 2,
      ).encode().toInt();

      for (int i = 0; i < IOTile.CONFIG_WIDTH; i++) {
        cfgIn.put((configBits >> i) & 1);
        await clk.nextPosedge;
      }
      cfgLoad.put(1);
      await clk.nextPosedge;
      cfgLoad.put(0);
      await clk.nextPosedge;

      fabricIn.put(0x4);
      await clk.nextPosedge;

      expect(tile.padOut.value.toInt(), 1);
      expect(tile.padOutputEnable.value.toInt(), 1);

      await Simulator.endSimulation();
    });

    test('hi-Z mode', () async {
      final clk = SimpleClockGenerator(10).clk;
      final reset = Logic();
      final cfgIn = Logic();
      final cfgLoad = Logic();
      final padIn = Logic();
      final fabricIn = Logic(width: 4);

      final tile = IOTile(
        clk,
        reset,
        cfgIn,
        cfgLoad,
        padIn: padIn,
        fabricIn: fabricIn,
        tracks: 4,
      );
      await tile.build();

      unawaited(Simulator.run());

      reset.put(1);
      cfgIn.put(0);
      cfgLoad.put(0);
      padIn.put(1);
      fabricIn.put(0xF);
      await clk.nextPosedge;
      reset.put(0);
      await clk.nextPosedge;
      await clk.nextPosedge;

      expect(tile.padOutputEnable.value.toInt(), 0);
      expect(tile.padOut.value.toInt(), 0);
      expect(tile.fabricOut.value.toInt(), 0);

      await Simulator.endSimulation();
    });
  });
}
