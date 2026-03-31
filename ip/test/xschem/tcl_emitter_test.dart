import 'package:aegis_ip/aegis_ip.dart';
import 'package:test/test.dart';

void main() {
  group('XschemTclEmitter', () {
    final pdk = GenericPdkProvider(symbolBasePath: '/test/symbols');

    test('generates TCL with FPGA instance', () {
      final emitter = XschemTclEmitter(
        deviceName: 'test_fpga',
        clockTileCount: 1,
        serdesCount: 2,
        totalPads: 8,
        width: 2,
        height: 2,
        pdk: pdk,
      );

      final tcl = emitter.generate();
      expect(tcl, contains('xschem clear'));
      expect(tcl, contains('xschem instance test_fpga.sym'));
      expect(tcl, contains('xschem saveas test_fpga-xschem.sch'));
    });

    test('places PLL instances', () {
      final emitter = XschemTclEmitter(
        deviceName: 'test_fpga',
        clockTileCount: 2,
        serdesCount: 0,
        totalPads: 8,
        width: 2,
        height: 2,
        pdk: pdk,
      );

      final tcl = emitter.generate();
      expect(tcl, contains('/test/symbols/aegis_pll.sym'));
      expect(tcl, contains('name=pll_0'));
      expect(tcl, contains('name=pll_1'));
    });

    test('places SerDes instances', () {
      final emitter = XschemTclEmitter(
        deviceName: 'test_fpga',
        clockTileCount: 0,
        serdesCount: 4,
        totalPads: 8,
        width: 2,
        height: 2,
        pdk: pdk,
      );

      final tcl = emitter.generate();
      expect(tcl, contains('/test/symbols/aegis_serdes.sym'));
      expect(tcl, contains('name=serdes_0'));
      expect(tcl, contains('name=serdes_3'));
    });

    test('places I/O cells', () {
      final emitter = XschemTclEmitter(
        deviceName: 'test_fpga',
        clockTileCount: 0,
        serdesCount: 0,
        totalPads: 8,
        width: 2,
        height: 2,
        pdk: pdk,
      );

      final tcl = emitter.generate();
      expect(tcl, contains('/test/symbols/aegis_io_cell.sym'));
      expect(tcl, contains('name=io_0'));
      expect(tcl, contains('name=io_7'));
    });

    test('generates wire commands for PLLs', () {
      final emitter = XschemTclEmitter(
        deviceName: 'test_fpga',
        clockTileCount: 1,
        serdesCount: 0,
        totalPads: 8,
        width: 2,
        height: 2,
        pdk: pdk,
      );

      final tcl = emitter.generate();
      expect(tcl, contains('xschem wire'));
    });

    test('skips sections with zero count', () {
      final emitter = XschemTclEmitter(
        deviceName: 'test_fpga',
        clockTileCount: 0,
        serdesCount: 0,
        totalPads: 0,
        width: 0,
        height: 0,
        pdk: pdk,
      );

      final tcl = emitter.generate();
      expect(tcl, isNot(contains('PLL instances')));
      expect(tcl, isNot(contains('SerDes instances')));
      expect(tcl, isNot(contains('I/O cell instances')));
    });
  });
}
