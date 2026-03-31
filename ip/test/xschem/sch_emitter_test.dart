import 'package:aegis_ip/aegis_ip.dart';
import 'package:test/test.dart';

void main() {
  group('XschemSchEmitter', () {
    final pdk = GenericPdkProvider(symbolBasePath: '/test/symbols');

    test('generates valid .sch header', () {
      final emitter = XschemSchEmitter(
        deviceName: 'test_fpga',
        clockTileCount: 1,
        serdesCount: 2,
        totalPads: 8,
        width: 2,
        height: 2,
        pdk: pdk,
      );

      final sch = emitter.generate();
      expect(sch, startsWith('v {xschem version=3.4.6}'));
      expect(sch, contains('G {}'));
    });

    test('places FPGA instance', () {
      final emitter = XschemSchEmitter(
        deviceName: 'test_fpga',
        clockTileCount: 1,
        serdesCount: 0,
        totalPads: 4,
        width: 1,
        height: 1,
        pdk: pdk,
      );

      final sch = emitter.generate();
      expect(sch, contains('C {test_fpga.sym}'));
      expect(sch, contains('name=test_fpga'));
    });

    test('places all analog block types', () {
      final emitter = XschemSchEmitter(
        deviceName: 'test_fpga',
        clockTileCount: 1,
        serdesCount: 2,
        totalPads: 8,
        width: 2,
        height: 2,
        pdk: pdk,
      );

      final sch = emitter.generate();
      expect(sch, contains('/test/symbols/aegis_pll.sym'));
      expect(sch, contains('/test/symbols/aegis_serdes.sym'));
      expect(sch, contains('/test/symbols/aegis_io_cell.sym'));
    });

    test('generates net labels', () {
      final emitter = XschemSchEmitter(
        deviceName: 'test_fpga',
        clockTileCount: 1,
        serdesCount: 1,
        totalPads: 4,
        width: 1,
        height: 1,
        pdk: pdk,
      );

      final sch = emitter.generate();
      expect(sch, contains('lab='));
    });
  });
}
