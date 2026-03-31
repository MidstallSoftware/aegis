import 'package:aegis_ip/aegis_ip.dart';
import 'package:rohd/rohd.dart';
import 'package:rohd_hcl/rohd_hcl.dart';
import 'package:test/test.dart';

void main() {
  tearDown(() async {
    await Simulator.reset();
  });

  group('PinMapping', () {
    test('default constructor', () {
      const pin = PinMapping('gpio0', 0, 0, Direction.north);
      expect(pin.name, 'gpio0');
      expect(pin.x, 0);
      expect(pin.y, 0);
      expect(pin.axis, Direction.north);
      expect(pin.track, 0);
      expect(pin.mode, PinMode.inout);
    });

    test('input constructor', () {
      const pin = PinMapping.input('rx', 1, 2, Direction.east, track: 3);
      expect(pin.mode, PinMode.input);
      expect(pin.track, 3);
    });

    test('output constructor', () {
      const pin = PinMapping.output('tx', 3, 4, Direction.west);
      expect(pin.mode, PinMode.output);
    });
  });

  group('AegisFPGA', () {
    test('builds and generates SV', () async {
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
        padIn: Logic(width: 2 * 2 + 2 * 2),
        serialIn: serialIn,
        configReadPort: configReadPort,
      );
      await fpga.build();

      final sv = fpga.generateSynth();
      expect(sv, contains('module AegisFPGA'));
      expect(sv, contains('module Tile'));
      expect(sv, contains('module IOTile'));
      expect(sv, contains('module SerDesTile'));
    });

    test('builds with BRAM', () async {
      final clk = Logic();
      final reset = Logic();
      final serialIn = Logic(width: 4);
      final configReadPort = DataPortInterface(8, 8);

      final fpga = AegisFPGA(
        clk,
        reset,
        width: 8,
        height: 2,
        tracks: 16,
        bramColumnInterval: 4,
        padIn: Logic(width: 2 * 8 + 2 * 2),
        serialIn: serialIn,
        configReadPort: configReadPort,
      );
      await fpga.build();

      final sv = fpga.generateSynth();
      expect(sv, contains('module BramTile'));
    });

    test('builds with configClk', () async {
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
        padIn: Logic(width: 8),
        serialIn: serialIn,
        configClk: Logic(),
        configReadPort: configReadPort,
      );
      await fpga.build();

      final sv = fpga.generateSynth();
      expect(sv, contains('configClk'));
    });
  });
}
