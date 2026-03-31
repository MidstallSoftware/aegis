import 'dart:async';
import 'package:aegis_ip/aegis_ip.dart';
import 'package:rohd/rohd.dart';
import 'package:rohd_hcl/rohd_hcl.dart';
import 'package:test/test.dart';

void main() {
  tearDown(() async {
    await Simulator.reset();
  });

  group('ClockTile', () {
    test('outputs stay low when disabled', () async {
      final clk = SimpleClockGenerator(10).clk;
      final reset = Logic();
      final cfgIn = Logic();
      final cfgLoad = Logic();

      final ct = ClockTile(clk, reset, cfgIn, cfgLoad);
      await ct.build();

      unawaited(Simulator.run());

      reset.put(1);
      cfgIn.put(0);
      cfgLoad.put(0);
      await clk.nextPosedge;
      reset.put(0);

      for (int i = 0; i < 10; i++) {
        await clk.nextPosedge;
      }

      expect(ct.clkOut.value.toInt(), 0);
      expect(ct.locked.value.toInt(), 0);

      await Simulator.endSimulation();
    });

    test('divide-by-2 output toggles', () async {
      final clk = SimpleClockGenerator(10).clk;
      final reset = Logic();
      final cfgIn = Logic();
      final cfgLoad = Logic();

      final ct = ClockTile(clk, reset, cfgIn, cfgLoad);
      await ct.build();

      unawaited(Simulator.run());

      reset.put(1);
      cfgIn.put(0);
      cfgLoad.put(0);
      await clk.nextPosedge;
      reset.put(0);
      await clk.nextPosedge;

      // Load config: global enable + output 0 enable + divider=2 + 50% duty
      final cfg = ClockTileConfig.divBy2.encode().toInt();

      // Shift in CONFIG_WIDTH bits
      for (int i = 0; i < ClockTile.CONFIG_WIDTH; i++) {
        cfgIn.put((cfg >> i) & 1);
        await clk.nextPosedge;
      }
      cfgLoad.put(1);
      await clk.nextPosedge;
      cfgLoad.put(0);
      await clk.nextPosedge;

      // Let the divider run for several cycles and sample clkOut[0]
      final samples = <int>[];
      for (int i = 0; i < 12; i++) {
        await clk.nextPosedge;
        samples.add(ct.clkOut.value.toInt() & 1);
      }

      // With divide-by-2 and 50% duty, output 0 should toggle
      // (not all zeros, not all ones)
      expect(samples.contains(0), true, reason: 'should have low periods');
      expect(samples.contains(1), true, reason: 'should have high periods');

      await Simulator.endSimulation();
    });

    test('locked goes high after cycle completes', () async {
      final clk = SimpleClockGenerator(10).clk;
      final reset = Logic();
      final cfgIn = Logic();
      final cfgLoad = Logic();

      final ct = ClockTile(clk, reset, cfgIn, cfgLoad);
      await ct.build();

      unawaited(Simulator.run());

      reset.put(1);
      cfgIn.put(0);
      cfgLoad.put(0);
      await clk.nextPosedge;
      reset.put(0);
      await clk.nextPosedge;

      // Config: global enable, output 0 enable, divider=1, 50% duty
      final cfg = const ClockTileConfig(
        enable: true,
        outputs: [
          ClockOutputConfig(enable: true, divider: 1, fiftyPercentDuty: true),
          ClockOutputConfig(),
          ClockOutputConfig(),
          ClockOutputConfig(),
        ],
      ).encode().toInt();

      for (int i = 0; i < ClockTile.CONFIG_WIDTH; i++) {
        cfgIn.put((cfg >> i) & 1);
        await clk.nextPosedge;
      }
      cfgLoad.put(1);
      await clk.nextPosedge;
      cfgLoad.put(0);

      // Wait for lock
      for (int i = 0; i < 10; i++) {
        await clk.nextPosedge;
        if (ct.locked.value.toInt() == 1) break;
      }

      expect(ct.locked.value.toInt(), 1);

      await Simulator.endSimulation();
    });

    test('config chain passes through', () async {
      final clk = SimpleClockGenerator(10).clk;
      final reset = Logic();
      final cfgIn = Logic();
      final cfgLoad = Logic();

      final ct = ClockTile(clk, reset, cfgIn, cfgLoad);
      await ct.build();

      unawaited(Simulator.run());

      reset.put(1);
      cfgIn.put(0);
      cfgLoad.put(0);
      await clk.nextPosedge;
      reset.put(0);
      await clk.nextPosedge;

      // Shift CONFIG_WIDTH ones through
      for (int i = 0; i < ClockTile.CONFIG_WIDTH; i++) {
        cfgIn.put(1);
        await clk.nextPosedge;
      }

      expect(ct.cfgOut.value.toInt(), 1);

      await Simulator.endSimulation();
    });

    test('multiple clock tiles in FPGA', () async {
      final clk = Logic();
      final reset = Logic();
      final serialIn = Logic(width: 4);
      final configReadPort = DataPortInterface(8, 8);

      final fpga = AegisFPGA(
        clk,
        reset,
        width: 2,
        height: 2,
        tracks: 4,
        clockTileCount: 2,
        padIn: Logic(width: 8),
        serialIn: serialIn,
        configReadPort: configReadPort,
      );
      await fpga.build();

      final sv = fpga.generateSynth();
      expect(sv, contains('module ClockTile'));
      // 2 clock tiles × 4 outputs = 8-bit clkOut
      expect(sv, contains('[7:0] clkOut'));
      expect(sv, contains('[1:0] clkLocked'));
    });
  });

  group('ClockTileConfig', () {
    test('default disabled', () {
      const cfg = ClockTileConfig();
      expect(cfg.enable, false);
      expect(cfg.outputs.length, 4);
      for (final o in cfg.outputs) {
        expect(o.enable, false);
      }
    });

    test('encode/decode round-trip', () {
      const cfg = ClockTileConfig(
        enable: true,
        outputs: [
          ClockOutputConfig(
            enable: true,
            divider: 100,
            phase: ClockPhase.deg90,
            fiftyPercentDuty: true,
          ),
          ClockOutputConfig(
            enable: true,
            divider: 50,
            phase: ClockPhase.deg180,
            fiftyPercentDuty: false,
          ),
          ClockOutputConfig(
            enable: false,
            divider: 200,
            phase: ClockPhase.deg270,
          ),
          ClockOutputConfig(enable: true, divider: 1),
        ],
      );

      final decoded = ClockTileConfig.decode(cfg.encode());
      expect(decoded.enable, true);
      expect(decoded.outputs[0].enable, true);
      expect(decoded.outputs[0].divider, 100);
      expect(decoded.outputs[0].phase, ClockPhase.deg90);
      expect(decoded.outputs[0].fiftyPercentDuty, true);
      expect(decoded.outputs[1].enable, true);
      expect(decoded.outputs[1].divider, 50);
      expect(decoded.outputs[1].phase, ClockPhase.deg180);
      expect(decoded.outputs[1].fiftyPercentDuty, false);
      expect(decoded.outputs[2].enable, false);
      expect(decoded.outputs[2].divider, 200);
      expect(decoded.outputs[2].phase, ClockPhase.deg270);
      expect(decoded.outputs[3].enable, true);
      expect(decoded.outputs[3].divider, 1);
    });

    test('presets', () {
      expect(ClockTileConfig.divBy2.enable, true);
      expect(ClockTileConfig.divBy2.outputs[0].divider, 2);
      expect(ClockTileConfig.divBy2.outputs[0].enable, true);
      expect(ClockTileConfig.divBy2.outputs[1].enable, false);

      expect(ClockTileConfig.quadDivider.enable, true);
      expect(ClockTileConfig.quadDivider.outputs[0].divider, 1);
      expect(ClockTileConfig.quadDivider.outputs[1].divider, 2);
      expect(ClockTileConfig.quadDivider.outputs[2].divider, 4);
      expect(ClockTileConfig.quadDivider.outputs[3].divider, 8);
    });

    test('fits in CONFIG_WIDTH bits', () {
      const cfg = ClockTileConfig(
        enable: true,
        outputs: [
          ClockOutputConfig(
            enable: true,
            divider: 256,
            phase: ClockPhase.deg270,
            fiftyPercentDuty: true,
          ),
          ClockOutputConfig(
            enable: true,
            divider: 256,
            phase: ClockPhase.deg270,
            fiftyPercentDuty: true,
          ),
          ClockOutputConfig(
            enable: true,
            divider: 256,
            phase: ClockPhase.deg270,
            fiftyPercentDuty: true,
          ),
          ClockOutputConfig(
            enable: true,
            divider: 256,
            phase: ClockPhase.deg270,
            fiftyPercentDuty: true,
          ),
        ],
      );
      expect(cfg.encode() < (BigInt.one << ClockTileConfig.width), true);
    });

    test('toString', () {
      expect(ClockTileConfig.divBy2.toString(), contains('ClockTileConfig'));
    });
  });
}
